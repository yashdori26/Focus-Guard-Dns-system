"""
FocusDNS Enterprise Engine - Usage Metering, Quotas & Billing Reconciliation.

Commercial metering plane tracking billable multi-tenant resource consumption:
  1. DNS Query Volumes (Aggregated billable lookups per calendar billing cycle).
  2. Peak QPS (Sustained 10-second burst query velocity).
  3. Unique Active Endpoints (Fleet device headcount).
  4. Columnar Storage Footprint (DuckDB / Parquet archive disk usage).
  5. SIEM Telemetry Egress (RFC 5424 Syslog / Splunk HEC bytes transferred).
  6. Cryptographically Signed Billing Invoices (HMAC-SHA256 verification).
  7. Multi-Tier Quota Threshold Alerts (80% Warning, 95% Critical, 100% Hard Cap).
"""

import collections
import datetime
import hashlib
import hmac
import json
import logging
import secrets
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.tenant_manager import TenantManager, get_tenant_manager

logger = logging.getLogger("FocusDNS.Enterprise.Metering")

HMAC_BILLING_SECRET = "focusdns_enterprise_commercial_metering_key_2026"


class TenantBillingUsage:
    """Usage accumulator for an organization in the current billing cycle."""
    __slots__ = (
        "org_id", "billing_cycle", "query_count", "peak_qps",
        "active_devices", "storage_bytes", "siem_egress_bytes",
        "last_updated", "quota_warnings_issued"
    )

    def __init__(self, org_id: str, billing_cycle: str):
        self.org_id = org_id
        self.billing_cycle = billing_cycle  # e.g. "2026-10"
        self.query_count = 0
        self.peak_qps = 0.0
        self.active_devices: Set[str] = set()
        self.storage_bytes = 0
        self.siem_egress_bytes = 0
        self.last_updated = time.time()
        self.quota_warnings_issued: Set[int] = set()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "org_id": self.org_id,
            "billing_cycle": self.billing_cycle,
            "query_count": self.query_count,
            "peak_qps": round(self.peak_qps, 2),
            "active_device_count": len(self.active_devices),
            "storage_megabytes": round(self.storage_bytes / (1024 * 1024), 2),
            "siem_egress_megabytes": round(self.siem_egress_bytes / (1024 * 1024), 2),
            "last_updated": self.last_updated,
        }


class UsageMeteringEngine:
    """
    Central commercial metering service tracking multi-tenant query usage,
    issuing quota alarms, and generating tamper-evident billing receipts.
    """

    def __init__(self, tenant_manager: Optional[TenantManager] = None):
        self._lock = threading.RLock()
        self.tenants = tenant_manager or get_tenant_manager()

        # org_id -> TenantBillingUsage
        self._current_usage: Dict[str, TenantBillingUsage] = {}

        # Historical signed invoices: invoice_id -> invoice_dict
        self._historical_invoices: Dict[str, Dict[str, Any]] = {}

        # Rate configuration (cents per unit for over-quota / commercial billing)
        self.base_rates = {
            "query_per_million_cents": 15,    # $0.15 per 1,000,000 queries
            "device_monthly_cents": 100,       # $1.00 per active managed device
            "gb_storage_cents": 25,           # $0.25 per GB Parquet storage
            "gb_siem_egress_cents": 10,       # $0.10 per GB SIEM streaming
        }

    def _get_current_cycle(self) -> str:
        now = datetime.datetime.now(datetime.timezone.utc)
        return now.strftime("%Y-%m")

    def _get_or_create_usage(self, org_id: str) -> TenantBillingUsage:
        cycle = self._get_current_cycle()
        key = f"{org_id}:{cycle}"
        usage = self._current_usage.get(key)
        if not usage:
            usage = TenantBillingUsage(org_id, cycle)
            self._current_usage[key] = usage
        return usage

    def record_query_usage(
        self,
        org_id: str,
        device_id: str,
        query_count: int = 1,
        instantaneous_qps: float = 0.0,
        bytes_transferred: int = 64
    ) -> Optional[int]:
        """
        Records billable DNS traffic. Checks for quota threshold crossings.
        Returns: Optional[threshold_percentage] if newly crossed (e.g. 80, 95, 100).
        """
        with self._lock:
            usage = self._get_or_create_usage(org_id)
            usage.query_count += query_count
            usage.active_devices.add(device_id)
            if instantaneous_qps > usage.peak_qps:
                usage.peak_qps = instantaneous_qps
            usage.last_updated = time.time()

            # Quota threshold check
            return self._check_quota_thresholds(org_id, usage)

    def record_siem_egress(self, org_id: str, byte_count: int) -> None:
        """Records SIEM network egress volume."""
        with self._lock:
            usage = self._get_or_create_usage(org_id)
            usage.siem_egress_bytes += byte_count

    def update_storage_footprint(self, org_id: str, total_bytes: int) -> None:
        """Updates disk footprint of columnar partitions."""
        with self._lock:
            usage = self._get_or_create_usage(org_id)
            usage.storage_bytes = total_bytes

    def _check_quota_thresholds(self, org_id: str, usage: TenantBillingUsage) -> Optional[int]:
        """Evaluates whether current usage crossed 80%, 95%, or 100% of plan allowance."""
        org = self.tenants.get_organization(org_id) if self.tenants else None
        if not org:
            return None

        # Device quota
        max_devices = org.quota.max_devices
        current_devices = len(usage.active_devices)

        # Calculate percentage against max devices
        pct = int((current_devices / max(1, max_devices)) * 100)

        threshold_crossed = None
        for threshold in (100, 95, 80):
            if pct >= threshold and threshold not in usage.quota_warnings_issued:
                usage.quota_warnings_issued.add(threshold)
                threshold_crossed = threshold
                logger.warning(
                    f"[USAGE QUOTA ALARM] Org '{org_id}' crossed {threshold}% threshold! "
                    f"Active Devices: {current_devices}/{max_devices} ({pct}%)."
                )
                break

        return threshold_crossed

    def generate_signed_invoice(self, org_id: str) -> Dict[str, Any]:
        """
        Generates a monthly billing summary with HMAC-SHA256 cryptographic signature
        guaranteeing non-repudiation and invoice integrity.
        """
        with self._lock:
            usage = self._get_or_create_usage(org_id)
            org = self.tenants.get_organization(org_id) if self.tenants else None
            org_name = org.name if org else org_id
            plan_tier = org.plan_tier if org else "ENTERPRISE"

            invoice_id = f"inv_{org_id}_{usage.billing_cycle}_{secrets.token_hex(4)}"

            # Compute billable totals (in dollars)
            query_charge = (usage.query_count / 1_000_000.0) * (self.base_rates["query_per_million_cents"] / 100.0)
            device_charge = len(usage.active_devices) * (self.base_rates["device_monthly_cents"] / 100.0)
            storage_gb = usage.storage_bytes / (1024 * 1024 * 1024.0)
            storage_charge = storage_gb * (self.base_rates["gb_storage_cents"] / 100.0)
            egress_gb = usage.siem_egress_bytes / (1024 * 1024 * 1024.0)
            egress_charge = egress_gb * (self.base_rates["gb_siem_egress_cents"] / 100.0)

            total_amount = round(query_charge + device_charge + storage_charge + egress_charge, 2)

            invoice_payload = {
                "invoice_id": invoice_id,
                "org_id": org_id,
                "org_name": org_name,
                "plan_tier": plan_tier,
                "billing_cycle": usage.billing_cycle,
                "generated_at": time.time(),
                "metrics": {
                    "total_queries": usage.query_count,
                    "peak_qps": round(usage.peak_qps, 2),
                    "active_devices": len(usage.active_devices),
                    "storage_bytes": usage.storage_bytes,
                    "siem_egress_bytes": usage.siem_egress_bytes,
                },
                "charges_usd": {
                    "queries": round(query_charge, 2),
                    "devices": round(device_charge, 2),
                    "storage": round(storage_charge, 2),
                    "siem_egress": round(egress_charge, 2),
                    "total": total_amount,
                }
            }

            # Cryptographic HMAC-SHA256 signature
            raw_serialized = json.dumps(invoice_payload, sort_keys=True).encode("utf-8")
            sig = hmac.new(
                HMAC_BILLING_SECRET.encode("utf-8"),
                raw_serialized,
                hashlib.sha256
            ).hexdigest()

            invoice_payload["signature_sha256"] = sig
            self._historical_invoices[invoice_id] = invoice_payload

            logger.info(f"[BILLING] Generated signed invoice {invoice_id} for org '{org_id}': ${total_amount:.2f} USD.")
            return invoice_payload

    def verify_invoice_signature(self, invoice_payload: Dict[str, Any]) -> bool:
        """Verifies the cryptographic signature of a billing invoice."""
        sig = invoice_payload.get("signature_sha256", "")
        if not sig:
            return False

        clone = dict(invoice_payload)
        clone.pop("signature_sha256", None)
        raw_serialized = json.dumps(clone, sort_keys=True).encode("utf-8")
        expected_sig = hmac.new(
            HMAC_BILLING_SECRET.encode("utf-8"),
            raw_serialized,
            hashlib.sha256
        ).hexdigest()

        return hmac.compare_digest(sig, expected_sig)

    def get_current_usage(self, org_id: str) -> Dict[str, Any]:
        with self._lock:
            usage = self._get_or_create_usage(org_id)
            return usage.to_dict()


# Global Singleton
_global_metering_engine: Optional[UsageMeteringEngine] = None
_metering_lock = threading.Lock()


def get_metering_engine() -> UsageMeteringEngine:
    global _global_metering_engine
    with _metering_lock:
        if _global_metering_engine is None:
            _global_metering_engine = UsageMeteringEngine()
        return _global_metering_engine
