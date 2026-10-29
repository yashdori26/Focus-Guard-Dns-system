"""
FocusDNS Enterprise Engine - Columnar Parquet Compactor & Partition Archiver.

Compresses live columnar query data into partitioned, immutable Parquet files
optimized for long-term cold storage retention, analytics federation, and data lakes.

Features:
  1. Hive-style Date & Tenant Partitioning:
     /var/log/focusdns/parquet/tenant={tenant_id}/year={YYYY}/month={MM}/queries-{uuid}.parquet
  2. ZSTD (Zstandard) and Snappy Columnar Compression:
     Achieves up to 15x compression ratios on repetitive DNS telemetry.
  3. Fast Partition Pruning Reader:
     Executes federated SQL queries across historical on-disk Parquet files.
  4. Retention Window Enforcement:
     Automatically prunes Parquet partition files exceeding tenant retention policies.
"""

import datetime
import logging
import os
import secrets
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.columnar_analytics import DnsQueryEvent, HAS_DUCKDB

logger = logging.getLogger("FocusDNS.Enterprise.ParquetArchiver")

DEFAULT_ARCHIVE_DIR = "/tmp/focusdns/enterprise/parquet_archive"


class ParquetArchiver:
    """
    Manages partitioning, compaction, and lifecycle pruning of historical
    DNS telemetry files using DuckDB's native Parquet engine.
    """

    def __init__(self, base_dir: str = DEFAULT_ARCHIVE_DIR):
        self.base_dir = base_dir
        self._lock = threading.RLock()
        os.makedirs(self.base_dir, exist_ok=True)

    def get_partition_path(self, tenant_id: str, timestamp_s: float) -> str:
        """Constructs Hive-style partition directory: tenant=X/year=Y/month=M."""
        dt = datetime.datetime.fromtimestamp(timestamp_s, datetime.timezone.utc)
        partition_dir = os.path.join(
            self.base_dir,
            f"tenant={tenant_id}",
            f"year={dt.year:04d}",
            f"month={dt.month:02d}",
            f"day={dt.day:02d}"
        )
        os.makedirs(partition_dir, exist_ok=True)
        return partition_dir

    def export_batch_to_parquet(
        self,
        tenant_id: str,
        events: List[DnsQueryEvent],
        compression: str = "ZSTD"
    ) -> Optional[str]:
        """
        Dumps a batch of query events directly into a compressed Parquet partition.
        Returns the absolute filepath of the generated Parquet file.
        """
        if not events or not HAS_DUCKDB:
            return None

        import duckdb
        timestamp_s = events[0].timestamp_us / 1_000_000
        partition_dir = self.get_partition_path(tenant_id, timestamp_s)
        filename = f"queries_{int(time.time())}_{secrets.token_hex(4)}.parquet"
        file_path = os.path.join(partition_dir, filename)

        tuples = [ev.to_tuple() for ev in events]

        with self._lock:
            temp_conn = duckdb.connect()
            temp_conn.execute("""
            CREATE TEMP TABLE temp_batch (
                timestamp_us BIGINT,
                tenant_id VARCHAR,
                sub_tenant_id VARCHAR,
                device_id VARCHAR,
                client_ip VARCHAR,
                domain VARCHAR,
                qtype VARCHAR,
                rcode VARCHAR,
                action VARCHAR,
                threat_type VARCHAR,
                category VARCHAR,
                latency_us INTEGER,
                bytes_transferred INTEGER
            );
            """)

            app = temp_conn.appender("temp_batch")
            app.append_rows(tuples)
            app.flush()

            # Export to Parquet with compression
            temp_conn.execute(f"""
            COPY temp_batch TO '{file_path}' (FORMAT PARQUET, COMPRESSION '{compression}');
            """)
            temp_conn.close()

        logger.info(f"Archived {len(events)} events to Parquet: {file_path}")
        return file_path

    def query_historical_parquet(
        self,
        tenant_id: str,
        sql_query: str
    ) -> List[Tuple[Any, ...]]:
        """
        Executes analytical SQL directly against all Parquet files for a tenant.
        Leverages DuckDB's vectorized Parquet scanner and partition pruning.
        """
        if not HAS_DUCKDB:
            return []

        import duckdb
        glob_path = os.path.join(self.base_dir, f"tenant={tenant_id}", "**", "*.parquet")

        with self._lock:
            conn = duckdb.connect()
            try:
                # Replace 'queries' table identifier with the parquet file glob
                formatted_sql = sql_query.replace(
                    "queries",
                    f"read_parquet('{glob_path}', hive_partitioning=1)"
                )
                rows = conn.execute(formatted_sql).fetchall()
                conn.close()
                return rows
            except Exception as e:
                logger.error(f"Error querying Parquet archives: {e}")
                conn.close()
                return []

    def enforce_retention(self, tenant_id: str, max_retention_days: int) -> int:
        """Prunes historical Parquet files older than max_retention_days."""
        tenant_dir = os.path.join(self.base_dir, f"tenant={tenant_id}")
        if not os.path.exists(tenant_dir):
            return 0

        cutoff_s = time.time() - (max_retention_days * 86400)
        pruned_files = 0

        with self._lock:
            for root, _, files in os.walk(tenant_dir):
                for f in files:
                    if f.endswith(".parquet"):
                        full_path = os.path.join(root, f)
                        try:
                            stat = os.stat(full_path)
                            if stat.st_mtime < cutoff_s:
                                os.unlink(full_path)
                                pruned_files += 1
                        except OSError:
                            pass

        if pruned_files > 0:
            logger.info(f"Enforced retention for {tenant_id}: pruned {pruned_files} expired Parquet partitions.")
        return pruned_files
