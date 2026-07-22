class TestimonialData {
  final String quote;
  final String name;
  final String role;
  final String initials;
  const TestimonialData({
    required this.quote,
    required this.name,
    required this.role,
    required this.initials,
  });
}

/// Illustrative placeholder testimonials — representative user voices for
/// a platform in the paper-trading/education category.
const List<TestimonialData> testimonials = [
  TestimonialData(
    quote:
        '"I started with zero market knowledge. Practicing intraday and F&O '
        'trades on Trade Kosh for a few months before touching real money '
        'made a huge difference to my confidence."',
    name: 'Ankit Sharma',
    role: 'Beginner Trader',
    initials: 'AS',
  ),
  TestimonialData(
    quote:
        '"The options chain and P&L analytics feel genuinely close to a '
        'real broker terminal. It\'s the best risk-free way I\'ve found to '
        'test new strategies."',
    name: 'Priya Nair',
    role: 'Options Trading Enthusiast',
    initials: 'PN',
  ),
  TestimonialData(
    quote:
        '"As someone who teaches a small trading community, I recommend '
        'Trade Kosh so my students can practice what they learn without any '
        'financial risk."',
    name: 'Rahul Verma',
    role: 'Market Educator',
    initials: 'RV',
  ),
  TestimonialData(
    quote:
        '"The structured lessons on risk management and psychology changed '
        'how I think about position sizing — something I wish I\'d learned '
        'before I started investing."',
    name: 'Sneha Patil',
    role: 'Long-term Investor',
    initials: 'SP',
  ),
  TestimonialData(
    quote:
        '"Clean interface, realistic order execution, and it\'s free to '
        'start. Perfect for testing a swing trading strategy before going '
        'live."',
    name: 'Vikram Iyer',
    role: 'Swing Trader',
    initials: 'VI',
  ),
];
