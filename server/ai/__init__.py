"""
FocusDNS AI Engine - On-Device Threat Hunting & Zero-Day Defense Subsystem
Exports:
- Unicode TR39 Confusable & Homograph Engine
- Zero-Hour Phishing & Brand Impersonation Detector
- On-Device DGA Neural Classifier & Markov Analyzer
- Dynamic Multi-Class Domain Categorizer
- Master Threat Hunting Engine & Coordinator
- Fast Tokenizer & Distance Metrics
- Model Checkpoint & Weight Serialization Manager
- AI Pipeline Hook
- AI REST API Dispatcher
"""

from .unicode_confusables import UnicodeConfusables, ScriptDetector
from .brand_dictionary import BrandDictionary
from .homograph_engine import HomographEngine, HomographResult
from .zero_hour_phishing import ZeroHourPhishingDetector, PhishingVerdict, LIFE_SAFETY_EXEMPTIONS
from .dga_families import DGAFamilyRegistry, SyntheticDGAGenerator
from .dga_neural_classifier import DGANeuralClassifier, DGAPrediction
from .category_lexicon import CategoryLexicon
from .domain_categorizer import DomainCategorizer, CategoryPrediction
from .threat_hunting_engine import ThreatHuntingEngine, ThreatVerdict, get_global_threat_engine
from .fast_tokenizer import FastTokenizer, FastDistanceMetrics
from .model_checkpoint_manager import ModelCheckpointManager, ModelCheckpointError
from .api_ai_router import AIApiDispatcher

__all__ = [
    "UnicodeConfusables",
    "ScriptDetector",
    "BrandDictionary",
    "HomographEngine",
    "HomographResult",
    "ZeroHourPhishingDetector",
    "PhishingVerdict",
    "LIFE_SAFETY_EXEMPTIONS",
    "DGAFamilyRegistry",
    "SyntheticDGAGenerator",
    "DGANeuralClassifier",
    "DGAPrediction",
    "CategoryLexicon",
    "DomainCategorizer",
    "CategoryPrediction",
    "ThreatHuntingEngine",
    "ThreatVerdict",
    "get_global_threat_engine",
    "FastTokenizer",
    "FastDistanceMetrics",
    "ModelCheckpointManager",
    "ModelCheckpointError",
    "AIApiDispatcher",
]
