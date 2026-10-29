"""
FocusDNS AI Engine - Model Checkpoint & Weight Serialization Manager
Provides thread-safe atomic serialization, HMAC/SHA-256 cryptographic verification,
hot-reloading, and rollback capabilities for on-device threat hunting neural networks
and probabilistic models.
"""

import hashlib
import hmac
import json
import logging
import os
import shutil
import tempfile
import threading
import time
from typing import Dict, Any, Optional, Tuple, Callable

logger = logging.getLogger("FocusDNS.AI.CheckpointManager")


class ModelCheckpointError(Exception):
    """Raised when checkpoint loading, validation, or integrity verification fails."""
    pass


class ModelCheckpointManager:
    """
    Manages persistence, atomic updates, and runtime hot-reloading of AI model weights.
    Guarantees zero-downtime weight swaps and automatic rollback on corruption.
    """

    DEFAULT_HMAC_KEY = b"FocusDNS-ZeroDay-AI-SecretKey-2026"

    def __init__(
        self,
        checkpoint_dir: str = "/tmp/focusdns/ai_models",
        hmac_key: Optional[bytes] = None,
    ):
        self.checkpoint_dir = checkpoint_dir
        self.hmac_key = hmac_key or self.DEFAULT_HMAC_KEY
        self._lock = threading.RLock()
        self._active_models: Dict[str, Any] = {}
        self._model_versions: Dict[str, str] = {}
        self._hot_reload_listeners: Dict[str, list] = {}

        os.makedirs(self.checkpoint_dir, exist_ok=True)

    def compute_checksum(self, data_bytes: bytes) -> str:
        """Computes SHA-256 digest of payload."""
        return hashlib.sha256(data_bytes).hexdigest()

    def compute_hmac(self, data_bytes: bytes) -> str:
        """Computes cryptographic HMAC-SHA256 signature."""
        return hmac.new(self.hmac_key, data_bytes, hashlib.sha256).hexdigest()

    def save_checkpoint(
        self,
        model_name: str,
        version: str,
        weights_dict: Dict[str, Any],
        metadata: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        Atomically saves a model checkpoint to disk with HMAC signature and metadata.
        Returns the absolute filepath of the saved checkpoint.
        """
        with self._lock:
            meta = metadata or {}
            meta.update({
                "model_name": model_name,
                "version": version,
                "timestamp": int(time.time()),
                "parameter_count": self._count_parameters(weights_dict),
            })

            payload = {
                "header": {
                    "format_version": "1.0",
                    "model_name": model_name,
                    "version": version,
                    "created_at": meta["timestamp"],
                },
                "metadata": meta,
                "weights": weights_dict,
            }

            serialized = json.dumps(payload, sort_keys=True).encode("utf-8")
            digest = self.compute_checksum(serialized)
            signature = self.compute_hmac(serialized)

            checkpoint_envelope = {
                "sha256": digest,
                "hmac_sha256": signature,
                "payload": payload,
            }

            final_path = os.path.join(self.checkpoint_dir, f"{model_name}.model")
            backup_path = os.path.join(self.checkpoint_dir, f"{model_name}.model.bak")

            # Write atomically to a temporary file in the same filesystem
            temp_fd, temp_path = tempfile.mkstemp(
                dir=self.checkpoint_dir, prefix=f"{model_name}_tmp_"
            )
            try:
                with os.fdopen(temp_fd, "w", encoding="utf-8") as f:
                    json.dump(checkpoint_envelope, f, indent=2)

                # Keep previous version as backup if it exists
                if os.path.exists(final_path):
                    shutil.copy2(final_path, backup_path)

                # Atomic rename
                os.replace(temp_path, final_path)
            except Exception as e:
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                logger.error(f"Failed to save checkpoint for {model_name}: {e}")
                raise ModelCheckpointError(f"Save failed: {e}")

            self._model_versions[model_name] = version
            logger.info(f"Successfully saved checkpoint for {model_name} (v{version})")
            return final_path

    def load_checkpoint(
        self,
        model_name: str,
        verify_hmac: bool = True,
    ) -> Tuple[Dict[str, Any], Dict[str, Any]]:
        """
        Loads a checkpoint from disk, verifying SHA-256 and HMAC signatures.
        Returns: (weights_dict, metadata_dict)
        """
        with self._lock:
            final_path = os.path.join(self.checkpoint_dir, f"{model_name}.model")
            backup_path = os.path.join(self.checkpoint_dir, f"{model_name}.model.bak")

            if not os.path.exists(final_path):
                raise ModelCheckpointError(f"Checkpoint for '{model_name}' not found at {final_path}")

            try:
                weights, meta = self._read_and_verify_envelope(final_path, verify_hmac)
                self._model_versions[model_name] = meta.get("version", "unknown")
                return weights, meta
            except Exception as primary_error:
                logger.warning(
                    f"Primary checkpoint for {model_name} corrupted ({primary_error}). Attempting rollback..."
                )
                if os.path.exists(backup_path):
                    try:
                        weights, meta = self._read_and_verify_envelope(backup_path, verify_hmac)
                        logger.info(f"Rollback to backup checkpoint for {model_name} succeeded.")
                        # Restore backup as primary
                        shutil.copy2(backup_path, final_path)
                        self._model_versions[model_name] = meta.get("version", "unknown-backup")
                        return weights, meta
                    except Exception as backup_error:
                        logger.error(f"Backup checkpoint also corrupted: {backup_error}")
                        raise ModelCheckpointError(f"Both primary and backup checkpoints corrupted: {primary_error} / {backup_error}")
                raise ModelCheckpointError(f"Corrupted checkpoint and no backup available: {primary_error}")

    def _read_and_verify_envelope(
        self, filepath: str, verify_hmac: bool
    ) -> Tuple[Dict[str, Any], Dict[str, Any]]:
        """Internal reader and integrity verifier."""
        with open(filepath, "r", encoding="utf-8") as f:
            envelope = json.load(f)

        if not isinstance(envelope, dict):
            raise ModelCheckpointError("Invalid checkpoint envelope format")

        expected_sha = envelope.get("sha256")
        expected_hmac = envelope.get("hmac_sha256")
        payload = envelope.get("payload")

        if not payload or not expected_sha or not expected_hmac:
            raise ModelCheckpointError("Missing required checkpoint headers")

        serialized = json.dumps(payload, sort_keys=True).encode("utf-8")
        actual_sha = self.compute_checksum(serialized)
        if actual_sha != expected_sha:
            raise ModelCheckpointError(
                f"SHA-256 digest mismatch: expected {expected_sha}, got {actual_sha}"
            )

        if verify_hmac:
            actual_hmac = self.compute_hmac(serialized)
            if not hmac.compare_digest(actual_hmac, expected_hmac):
                raise ModelCheckpointError("HMAC cryptographic signature validation failed")

        weights = payload.get("weights", {})
        metadata = payload.get("metadata", {})
        return weights, metadata

    def hot_reload(self, model_name: str, new_weights: Dict[str, Any], new_version: str):
        """
        Hot-reloads model weights in memory and fires registered listeners without dropping queries.
        """
        with self._lock:
            # First save atomically
            self.save_checkpoint(model_name, new_version, new_weights)
            self._active_models[model_name] = new_weights
            self._model_versions[model_name] = new_version

            listeners = self._hot_reload_listeners.get(model_name, [])
            for listener in listeners:
                try:
                    listener(new_weights, new_version)
                except Exception as e:
                    logger.error(f"Error in hot reload listener for {model_name}: {e}")

    def register_reload_listener(self, model_name: str, callback: Callable[[Dict[str, Any], str], None]):
        """Registers a callback invoked when hot_reload occurs for model_name."""
        with self._lock:
            if model_name not in self._hot_reload_listeners:
                self._hot_reload_listeners[model_name] = []
            self._hot_reload_listeners[model_name].append(callback)

    def get_version(self, model_name: str) -> Optional[str]:
        """Returns the currently active version of a model."""
        with self._lock:
            return self._model_versions.get(model_name)

    def export_bundle(self, export_filepath: str) -> int:
        """
        Exports all active model checkpoints into a unified archive bundle for backup or router syncing.
        Returns total number of models bundled.
        """
        with self._lock:
            models_to_bundle = {}
            for filename in os.listdir(self.checkpoint_dir):
                if filename.endswith(".model"):
                    model_path = os.path.join(self.checkpoint_dir, filename)
                    try:
                        with open(model_path, "r", encoding="utf-8") as f:
                            models_to_bundle[filename] = json.load(f)
                    except Exception as e:
                        logger.warning(f"Skipping {filename} in bundle export: {e}")

            bundle = {
                "exported_at": int(time.time()),
                "total_models": len(models_to_bundle),
                "models": models_to_bundle,
            }

            temp_fd, temp_path = tempfile.mkstemp(prefix="focusdns_bundle_")
            with os.fdopen(temp_fd, "w", encoding="utf-8") as f:
                json.dump(bundle, f, indent=2)

            os.replace(temp_path, export_filepath)
            return len(models_to_bundle)

    def import_bundle(self, import_filepath: str) -> int:
        """
        Imports and validates a model bundle archive, restoring checkpoints.
        Returns total number of models successfully imported.
        """
        with self._lock:
            if not os.path.exists(import_filepath):
                raise ModelCheckpointError(f"Bundle file not found: {import_filepath}")

            with open(import_filepath, "r", encoding="utf-8") as f:
                bundle = json.load(f)

            models = bundle.get("models", {})
            imported_count = 0
            for filename, envelope in models.items():
                target_path = os.path.join(self.checkpoint_dir, filename)
                try:
                    # Validate envelope structure
                    serialized = json.dumps(envelope["payload"], sort_keys=True).encode("utf-8")
                    calc_sha = self.compute_checksum(serialized)
                    if calc_sha == envelope.get("sha256"):
                        with open(target_path, "w", encoding="utf-8") as tf:
                            json.dump(envelope, tf, indent=2)
                        imported_count += 1
                except Exception as e:
                    logger.warning(f"Failed to import {filename} from bundle: {e}")

            return imported_count

    @staticmethod
    def _count_parameters(weights: Dict[str, Any]) -> int:
        """Recursively counts scalar numeric parameters in weight arrays."""
        count = 0
        for val in weights.values():
            if isinstance(val, (int, float)):
                count += 1
            elif isinstance(val, list):
                count += ModelCheckpointManager._count_list_elements(val)
            elif isinstance(val, dict):
                count += ModelCheckpointManager._count_parameters(val)
        return count

    @staticmethod
    def _count_list_elements(lst: list) -> int:
        count = 0
        for item in lst:
            if isinstance(item, (int, float)):
                count += 1
            elif isinstance(item, list):
                count += ModelCheckpointManager._count_list_elements(item)
        return count
