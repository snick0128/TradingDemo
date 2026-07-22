/// Placeholder/illustrative pricing — Trade Kosh is a paper trading &
/// education platform, not a brokerage, so pricing reflects access tiers
/// to simulation limits and learning content rather than trading fees.
class PricingPlan {
  final String name;
  final String price;
  final String period;
  final String description;
  final List<String> features;
  final bool highlighted;
  final String ctaLabel;

  const PricingPlan({
    required this.name,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
    required this.ctaLabel,
    this.highlighted = false,
  });
}

const pricingPlans = [
  PricingPlan(
    name: 'Free',
    price: '₹0',
    period: '/ forever',
    description: 'Everything you need to start practicing.',
    ctaLabel: 'Start Free',
    features: [
      'Full paper trading simulator (Equity, F&O, MCX)',
      '₹10,00,000 virtual starting capital',
      'Live-linked market data & charts',
      'Watchlists, order book & trade history',
      'Starter guides & video lessons',
      '1 portfolio reset per month',
    ],
  ),
  PricingPlan(
    name: 'Premium',
    price: '₹499',
    period: '/ month',
    description: 'For traders who want to go deeper, faster.',
    ctaLabel: 'Go Premium',
    highlighted: true,
    features: [
      'Everything in Free, plus:',
      'Full course library (all levels)',
      'Unlimited virtual portfolio resets',
      'Advanced analytics & brokerage/tax reports',
      'Priority access to new features',
      'Ad-free learning experience',
      'Progress tracking across courses (Coming Soon)',
      'Certificates of completion (Coming Soon)',
    ],
  ),
];
