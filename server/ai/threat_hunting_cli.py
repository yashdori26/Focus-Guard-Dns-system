"""
FocusDNS AI Engine - Threat Hunting Administrative CLI
Command-line utility for real-time threat hunting diagnostics, IDN homograph inspection,
DGA neural classification, benchmark profiling, model checkpoint management,
and Conditional Whitelisting Law enforcement.
"""

import argparse
import json
import os
import sys
import time
from typing import List, Dict, Any

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.threat_hunting_engine import ThreatHuntingEngine, ThreatVerdict, get_global_threat_engine
from server.ai.homograph_engine import HomographEngine
from server.ai.dga_neural_classifier import DgaNeuralClassifier
from server.ai.domain_categorizer import DomainCategorizer
from server.ai.zero_hour_phishing import ZeroHourPhishingDetector
from server.ai.model_checkpoint_manager import ModelCheckpointManager


def format_risk_bar(score: float, width: int = 20) -> str:
    """Renders visual ASCII risk bar."""
    filled = int(round((score / 100.0) * width))
    filled = min(width, max(0, filled))
    bar = "=" * filled + "-" * (width - filled)
    if score >= 75:
        color = "\033[91m"  # Red
    elif score >= 50:
        color = "\033[93m"  # Yellow
    else:
        color = "\033[92m"  # Green
    reset = "\033[0m"
    return f"{color}[{bar}] {score:5.1f}%{reset}"


def cmd_hunt(args, engine: ThreatHuntingEngine):
    """Executes full threat hunting assessment on a domain."""
    t0 = time.perf_counter()
    verdict: ThreatVerdict = engine.hunt_domain(args.domain)
    latency_us = (time.perf_counter() - t0) * 1_000_000

    print(f"\n================ FocusDNS AI Threat Hunt ================")
    print(f" Domain:             {verdict.domain}")
    print(f" Threat Detected:    {'YES' if verdict.is_threat else 'NO'}")
    print(f" Action:             {verdict.recommended_action}")
    print(f" Composite Risk:     {format_risk_bar(verdict.composite_risk_score)}")
    print(f" Threat Vector:      {verdict.threat_type}")
    print(f" Primary Reason:     {verdict.primary_reason}")
    if verdict.detected_brand:
        print(f" Targeted Brand:     {verdict.detected_brand.upper()}")
    if verdict.dga_family:
        print(f" DGA Family:         {verdict.dga_family}")
    print(f" Category:           {verdict.primary_category}")
    print(f" Distracting:        {'YES' if verdict.is_distracting else 'NO'}")
    print(f" Inference Latency:  {latency_us:,.1f} µs (Cached: {verdict.cached})")
    print(f"==========================================================\n")

    if args.json:
        print(json.dumps(verdict.to_dict(), indent=2))


def cmd_homograph(args):
    """Inspects Unicode TR39 lookalikes and typosquatting."""
    engine = HomographEngine()
    verdict = engine.analyze(args.domain)

    print(f"\n============= IDN Homograph & Typosquat Analysis =============")
    print(f" Input Domain:       {verdict.original_domain}")
    print(f" Unicode Domain:     {verdict.unicode_domain}")
    print(f" Skeleton:           {verdict.skeleton}")
    print(f" Threat Candidate:   {'YES' if verdict.is_threat else 'NO'}")
    print(f" Attack Type:        {verdict.attack_type}")
    print(f" Spoofed Brand:      {verdict.spoofed_brand or 'None'}")
    print(f" Risk Score:         {format_risk_bar(verdict.risk_score)}")
    print(f" Explanation:        {verdict.explanation}")
    print(f" Confusable Count:   {len(verdict.confusable_details)}")
    for c in verdict.confusable_details:
        print(f"   - Char '{c['character']}' ({c['codepoint']}) in {c['script']} -> maps to '{c['confusable_with']}'")
    print(f"==============================================================\n")


def cmd_dga(args):
    """Executes DGA Neural Classifier forward-pass."""
    classifier = DgaNeuralClassifier()
    verdict = classifier.predict(args.domain)

    print(f"\n================ DGA Neural Classifier ================")
    print(f" Domain:             {verdict.domain}")
    print(f" DGA Malware C2:     {'YES' if verdict.is_dga else 'NO'}")
    print(f" Probability:        {format_risk_bar(verdict.confidence_score)}")
    print(f" Attributed Family:  {verdict.predicted_family or 'Benign / Uncorrelated'}")
    print(f" Shannon Entropy:    {verdict.entropy:4.3f} bits/char")
    print(f" Vowel Ratio:        {verdict.vowel_ratio * 100:.1f}%")
    print(f" Explanation:        {verdict.explanation}")
    print(f"=======================================================\n")


def cmd_categorize(args):
    """Classifies domain across 8 standardized categories."""
    categorizer = DomainCategorizer()
    verdict = categorizer.predict(args.domain)

    print(f"\n============= Multi-Class Domain Categorization =============")
    print(f" Domain:             {verdict.domain}")
    print(f" Primary Category:   {verdict.primary_category}")
    print(f" Confidence:         {verdict.confidence * 100:.1f}%")
    print(f" Is Distracting:     {'YES' if verdict.is_distracting else 'NO'}")
    print(f" Probability Distribution:")
    for cat, p in sorted(verdict.category_probabilities.items(), key=lambda x: -x[1]):
        bar = format_risk_bar(p * 100, width=15)
        print(f"   {cat:<25} {bar}")
    print(f"=============================================================\n")


def cmd_lock(args, engine: ThreatHuntingEngine):
    """Enables active focus lock."""
    duration = args.duration
    engine.set_focus_lock(locked=True, remaining_seconds=duration)
    print(f"\033[93m[Focus Lock Active]\033[0m Active Focus lockdown enabled for {duration} seconds.")
    print("Under the Conditional Whitelisting Law, whitelist modifications are strictly forbidden.")


def cmd_unlock(args, engine: ThreatHuntingEngine):
    """Unlocks focus mode when allowed."""
    if engine.is_locked() and not args.force:
        print("\033[91m[Error]\033[0m Cannot unlock while active timer is running without --force flag!")
        sys.exit(1)
    engine.set_focus_lock(locked=False, remaining_seconds=0)
    print("\033[92m[Focus Idle]\033[0m System unlocked. Whitelisting modifications now permitted.")


def cmd_whitelist(args, engine: ThreatHuntingEngine):
    """Attempts to add domain to whitelist."""
    try:
        engine.add_whitelist(args.domain)
        print(f"\033[92m[Success]\033[0m Domain '{args.domain}' added to whitelist with 0 friction.")
    except PermissionError as pe:
        print(f"\033[91m[Access Denied]\033[0m {pe}")
        sys.exit(5)


def cmd_benchmark(args, engine: ThreatHuntingEngine):
    """Profiles latency and throughput."""
    count = args.count
    test_domains = [
        "google.com",
        "\u0430pple.com",
        "paypal.com.verify-account.security-update.xyz",
        "bcdfghjklmnpqrstvwxyz.org",
        "steampowered.com",
        "netflix.com",
        "github.com",
        "binance-wallet-auth.top",
    ]

    print(f"Running on-device AI Threat Hunting Benchmark ({count:,} queries)...")
    t0 = time.perf_counter()
    for i in range(count):
        d = test_domains[i % len(test_domains)]
        engine.hunt_domain(d)
    elapsed = time.perf_counter() - t0

    qps = count / max(0.0001, elapsed)
    avg_us = (elapsed / count) * 1_000_000
    print(f"\n================ Benchmark Results ================")
    print(f" Total Queries:      {count:,}")
    print(f" Elapsed Time:       {elapsed:.4f} seconds")
    print(f" Throughput:         {qps:,.0f} queries/sec")
    print(f" Average Latency:    {avg_us:.2f} µs per query")
    print(f"===================================================\n")


def main():
    parser = argparse.ArgumentParser(
        prog="focusguard-ai",
        description="FocusDNS AI Threat Hunting Diagnostic & Administration Tool"
    )
    subparsers = parser.add_subparsers(dest="command", help="Available subcommands")

    # hunt
    p_hunt = subparsers.add_parser("hunt", help="Perform comprehensive threat assessment")
    p_hunt.add_argument("domain", help="Domain name to analyze")
    p_hunt.add_argument("--json", action="store_true", help="Output raw JSON format")

    # homograph
    p_homo = subparsers.add_parser("homograph", help="Inspect TR39 confusables and typosquatting")
    p_homo.add_argument("domain", help="Domain name to inspect")

    # dga
    p_dga = subparsers.add_parser("dga", help="Classify algorithmic malware C2 domains")
    p_dga.add_argument("domain", help="Domain name to classify")

    # categorize
    p_cat = subparsers.add_parser("categorize", help="Classify domain into standardized categories")
    p_cat.add_argument("domain", help="Domain name to categorize")

    # lock
    p_lock = subparsers.add_parser("lock", help="Activate focus lockdown")
    p_lock.add_argument("duration", type=int, nargs="?", default=1800, help="Duration in seconds")

    # unlock
    p_unlock = subparsers.add_parser("unlock", help="Deactivate focus lockdown")
    p_unlock.add_argument("--force", action="store_true", help="Force emergency unlock")

    # whitelist
    p_wl = subparsers.add_parser("whitelist", help="Add domain to whitelist")
    p_wl.add_argument("domain", help="Domain to whitelist")

    # benchmark
    p_bench = subparsers.add_parser("benchmark", help="Run throughput benchmark")
    p_bench.add_argument("--count", type=int, default=10000, help="Number of benchmark queries")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    engine = get_global_threat_engine()

    if args.command == "hunt":
        cmd_hunt(args, engine)
    elif args.command == "homograph":
        cmd_homograph(args)
    elif args.command == "dga":
        cmd_dga(args)
    elif args.command == "categorize":
        cmd_categorize(args)
    elif args.command == "lock":
        cmd_lock(args, engine)
    elif args.command == "unlock":
        cmd_unlock(args, engine)
    elif args.command == "whitelist":
        cmd_whitelist(args, engine)
    elif args.command == "benchmark":
        cmd_benchmark(args, engine)


if __name__ == "__main__":
    main()
