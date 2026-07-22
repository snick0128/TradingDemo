/// Content data for all legal/compliance pages. Rendered by a single
/// generic LegalPageScaffold (see widgets/legal_page_scaffold.dart) driven
/// by slug — avoids 8 near-duplicate page files.
class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}

class LegalDoc {
  final String slug;
  final String title;
  final String lastUpdated;
  final List<LegalSection> sections;
  const LegalDoc({
    required this.slug,
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });
}

const String _kLastUpdated = 'July 22, 2026';
const String _kSupportEmail = 'support@tradekosh.com';
const String _kCompany = 'Trade Kosh';

const Map<String, LegalDoc> legalDocs = {
  'privacy-policy': LegalDoc(
    slug: 'privacy-policy',
    title: 'Privacy Policy',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. Introduction',
        '$_kCompany ("we", "us", "our") operates the Trade Kosh paper trading '
            'and stock market education platform (the "Platform"). This '
            'Privacy Policy explains what information we collect when you '
            'use the Platform, how we use it, and the choices you have. By '
            'creating an account or using the Platform, you agree to the '
            'collection and use of information in accordance with this policy.',
      ),
      LegalSection(
        '2. Information We Collect',
        'Account information: name, email address, phone number, and a '
            'password (stored in hashed form) when you register. Usage '
            'data: pages visited, features used, order/trade simulations '
            'placed within the Platform, watchlists, and learning progress. '
            'Device information: browser type, IP address, and device '
            'identifiers collected automatically for security and analytics. '
            'We do not collect bank account, card, or real brokerage '
            'credentials, because Trade Kosh does not place real trades or '
            'handle real securities.',
      ),
      LegalSection(
        '3. How We Use Information',
        'We use collected information to: provide and maintain the '
            'Platform; personalize your dashboard, watchlists, and virtual '
            'portfolio; send transactional emails (account verification, '
            'password resets, important notices); improve our educational '
            'content and simulation accuracy; detect and prevent fraud, '
            'abuse, or violations of our Terms & Conditions; and comply with '
            'legal obligations.',
      ),
      LegalSection(
        '4. Cookies and Tracking',
        'We use cookies and similar technologies to keep you signed in, '
            'remember preferences, and understand aggregate usage patterns. '
            'See our Cookie Policy for details on the categories of cookies '
            'used and how to manage them.',
      ),
      LegalSection(
        '5. Data Sharing',
        'We do not sell your personal information. We may share data with: '
            'service providers who help us operate the Platform (hosting, '
            'analytics, authentication, email delivery) under confidentiality '
            'obligations; and law enforcement or regulators where required by '
            'applicable law.',
      ),
      LegalSection(
        '6. Data Security',
        'We use industry-standard safeguards (encrypted transport, access '
            'controls, hashed credentials) to protect your information. No '
            'method of transmission or storage is 100% secure, and we cannot '
            'guarantee absolute security.',
      ),
      LegalSection(
        '7. Data Retention',
        'We retain account and usage data for as long as your account is '
            'active or as needed to provide the Platform, comply with legal '
            'obligations, resolve disputes, and enforce our agreements. You '
            'may request deletion of your account as described below.',
      ),
      LegalSection(
        '8. Your Rights',
        'You may access, correct, or request deletion of your personal '
            'information by contacting $_kSupportEmail. We will respond '
            'within a reasonable time and in accordance with applicable law.',
      ),
      LegalSection(
        '9. Children\'s Privacy',
        'The Platform is not directed at children under 18. We do not '
            'knowingly collect personal information from minors.',
      ),
      LegalSection(
        '10. Changes to This Policy',
        'We may update this Privacy Policy from time to time. Material '
            'changes will be notified via the Platform or email. Continued '
            'use after changes take effect constitutes acceptance.',
      ),
      LegalSection(
        '11. Contact Us',
        'Questions about this Privacy Policy can be sent to $_kSupportEmail.',
      ),
    ],
  ),

  'terms-conditions': LegalDoc(
    slug: 'terms-conditions',
    title: 'Terms & Conditions',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. Acceptance of Terms',
        'These Terms & Conditions ("Terms") govern your access to and use '
            'of the $_kCompany website and application (the "Platform"). By '
            'registering for or using the Platform, you agree to be bound by '
            'these Terms. If you do not agree, please do not use the Platform.',
      ),
      LegalSection(
        '2. Nature of the Service',
        '$_kCompany provides a simulated ("paper") trading environment and '
            'stock market education content for learning purposes only. All '
            'money, positions, orders, and portfolios on the Platform are '
            'virtual and carry no real monetary value. $_kCompany is not a '
            'stockbroker, depository participant, portfolio manager, or '
            'investment adviser, and does not execute any real trades or '
            'handle real securities or funds on behalf of any user.',
      ),
      LegalSection(
        '3. No Investment Advice',
        'Nothing on the Platform constitutes investment advice, a '
            'recommendation, or a solicitation to buy or sell any security. '
            'Market data, charts, and analytics are provided for educational '
            'and simulation purposes only. You are solely responsible for '
            'any real-world financial decisions you make, and should consult '
            'a SEBI-registered financial or investment adviser before '
            'investing real money.',
      ),
      LegalSection(
        '4. Eligibility and Account Registration',
        'You must be at least 18 years old and capable of forming a binding '
            'contract to create an account. You agree to provide accurate '
            'registration information and to keep your login credentials '
            'confidential. You are responsible for all activity under your '
            'account.',
      ),
      LegalSection(
        '5. Acceptable Use',
        'You agree not to: attempt to manipulate simulated market data or '
            'leaderboards; reverse-engineer, scrape, or interfere with the '
            'Platform\'s operation; use the Platform for any unlawful '
            'purpose; or misrepresent the Platform as a real brokerage or '
            'advisory service to any third party.',
      ),
      LegalSection(
        '6. Subscription Plans',
        'The Platform offers a Free plan and one or more optional paid '
            '("Premium") plans that unlock additional educational content, '
            'analytics, or simulation limits, as described on our Pricing '
            'page. Paid plans are billed as disclosed at the time of '
            'purchase and are governed by our Refund Policy and Cancellation '
            'Policy.',
      ),
      LegalSection(
        '7. Intellectual Property',
        'All content on the Platform — including text, graphics, course '
            'material, videos, logos, and software — is owned by or licensed '
            'to $_kCompany and is protected by applicable intellectual '
            'property laws. You may not reproduce, distribute, or create '
            'derivative works without prior written consent.',
      ),
      LegalSection(
        '8. Disclaimers and Limitation of Liability',
        'The Platform is provided "as is" without warranties of any kind. '
            'Simulated results, including paper trading P&L, do not '
            'guarantee similar results in live markets. To the maximum '
            'extent permitted by law, $_kCompany shall not be liable for any '
            'indirect, incidental, or consequential damages arising from '
            'your use of the Platform, including decisions made based on '
            'simulated performance.',
      ),
      LegalSection(
        '9. Termination',
        'We may suspend or terminate your account for violation of these '
            'Terms, suspected fraud, or misuse of the Platform, with or '
            'without notice, at our discretion.',
      ),
      LegalSection(
        '10. Governing Law',
        'These Terms are governed by the laws of India. Any disputes shall '
            'be subject to the exclusive jurisdiction of the courts located '
            'in India.',
      ),
      LegalSection(
        '11. Changes to These Terms',
        'We may revise these Terms periodically. Continued use of the '
            'Platform after changes are posted constitutes acceptance of the '
            'revised Terms.',
      ),
      LegalSection(
        '12. Contact',
        'For questions about these Terms, contact $_kSupportEmail.',
      ),
    ],
  ),

  'refund-policy': LegalDoc(
    slug: 'refund-policy',
    title: 'Refund Policy',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. Digital Subscription Services',
        '$_kCompany sells access to digital educational content and '
            'premium paper-trading features via subscription plans. Because '
            'these are digital services delivered instantly upon payment, '
            'refunds are handled as described below.',
      ),
      LegalSection(
        '2. Eligibility for Refund',
        'You may request a full refund within 7 days of your initial '
            'subscription purchase, provided you have not substantially '
            'used the premium features (e.g. accessed a majority of the '
            'paid course library or exceeded free-tier simulation limits '
            'materially). Renewal charges for subsequent billing cycles are '
            'refundable only if requested within 48 hours of the renewal '
            'charge.',
      ),
      LegalSection(
        '3. Non-Refundable Situations',
        'Refunds will not be granted where: the request is made after the '
            'applicable window above; the account was suspended for '
            'violating our Terms & Conditions; or the request relates to '
            'dissatisfaction with simulated trading outcomes, which by '
            'nature carry no real monetary value or guaranteed performance.',
      ),
      LegalSection(
        '4. How to Request a Refund',
        'Email $_kSupportEmail from your registered email address with your '
            'account details and reason for the refund request. We aim to '
            'respond within 3–5 business days.',
      ),
      LegalSection(
        '5. Refund Processing Time',
        'Approved refunds are processed to the original payment method '
            'within 7–10 business days, subject to your bank or payment '
            'provider\'s processing timelines.',
      ),
      LegalSection(
        '6. Free Plan',
        'The Free plan requires no payment and is therefore not subject to '
            'this Refund Policy.',
      ),
    ],
  ),

  'cancellation-policy': LegalDoc(
    slug: 'cancellation-policy',
    title: 'Cancellation Policy',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. Cancelling Your Subscription',
        'You may cancel your Premium subscription at any time from your '
            'Account Settings, or by emailing $_kSupportEmail. Cancellation '
            'stops future billing — it does not automatically trigger a '
            'refund for the current billing period (see our Refund Policy).',
      ),
      LegalSection(
        '2. Access After Cancellation',
        'When you cancel, you will continue to have access to Premium '
            'features until the end of your current paid billing cycle. '
            'After that, your account reverts to the Free plan; your '
            'virtual portfolio, watchlists, and learning progress are not '
            'deleted.',
      ),
      LegalSection(
        '3. Account Deletion',
        'You may request full account deletion at any time via '
            '$_kSupportEmail. This is separate from subscription '
            'cancellation and will permanently remove your profile, virtual '
            'portfolio, and associated data, subject to any legal retention '
            'obligations described in our Privacy Policy.',
      ),
      LegalSection(
        '4. Cancellation by $_kCompany',
        'We may cancel or suspend your access if we reasonably believe your '
            'account violates our Terms & Conditions, involves fraudulent '
            'activity, or poses a security risk to the Platform.',
      ),
    ],
  ),

  'shipping-delivery': LegalDoc(
    slug: 'shipping-delivery',
    title: 'Shipping & Delivery Policy',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. No Physical Products',
        '$_kCompany is a digital platform. We do not manufacture, sell, or '
            'ship any physical products. Nothing purchased on the Platform '
            'results in a physical shipment.',
      ),
      LegalSection(
        '2. Digital Delivery',
        'All services offered by $_kCompany — including account access, '
            'paper trading simulation, courses, videos, and premium '
            'features — are delivered electronically and are available '
            'immediately after successful account registration or payment, '
            'accessible via login on our website or application.',
      ),
      LegalSection(
        '3. Delivery Timeline',
        'Free-plan access is available immediately upon successful '
            'registration and email verification. Premium-plan features are '
            'unlocked immediately upon successful payment confirmation; in '
            'rare cases of payment-gateway delay, access is granted within '
            '24 hours once payment is confirmed.',
      ),
      LegalSection(
        '4. Delivery Issues',
        'If you complete a payment but do not receive access to purchased '
            'features within 24 hours, please contact $_kSupportEmail with '
            'your payment reference so we can investigate and resolve the '
            'issue promptly.',
      ),
    ],
  ),

  'disclaimer': LegalDoc(
    slug: 'disclaimer',
    title: 'Disclaimer',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. Educational and Simulated Platform Only',
        '$_kCompany is a paper trading simulation and stock market '
            'education platform. It is designed solely to help users learn '
            'about markets, trading concepts, and order types in a '
            'risk-free, virtual environment. All balances, positions, '
            'orders, and profit & loss figures shown on the Platform are '
            'simulated using virtual currency and have no real monetary '
            'value.',
      ),
      LegalSection(
        '2. Not a Broker, Advisor, or Portfolio Manager',
        '$_kCompany is not registered with, and does not act as, a '
            'stockbroker, depository participant, investment adviser, '
            'research analyst, or portfolio manager under the Securities and '
            'Exchange Board of India (SEBI) or any other regulator. We do '
            'not execute real orders in any exchange, hold real securities, '
            'or manage real client funds.',
      ),
      LegalSection(
        '3. No Investment Advice or Recommendations',
        'Nothing on the Platform — including market data, charts, screens, '
            'options-chain analytics, or educational content — should be '
            'construed as investment advice, a stock tip, a buy/sell '
            'recommendation, or a solicitation to trade or invest. Any '
            'similarity between simulated exercises and real securities is '
            'for educational illustration only.',
      ),
      LegalSection(
        '4. No Guaranteed Returns',
        '$_kCompany does not guarantee, promise, or imply any specific '
            'outcome, profit, or return — simulated or otherwise. Past '
            'performance of any simulated strategy, instrument, or the '
            'overall stock market does not guarantee or indicate future '
            'results in real markets.',
      ),
      LegalSection(
        '5. Paper Trading Differs From Live Trading',
        'Simulated trading does not account for real-world factors such as '
            'liquidity constraints, slippage beyond our modeled estimate, '
            'emotional decision-making under real financial risk, exact '
            'order-matching behavior of live exchanges, brokerage costs, '
            'taxes, or regulatory margin requirements. Performance in the '
            'simulator should never be relied upon as a predictor of '
            'performance with real capital.',
      ),
      LegalSection(
        '6. Trading Involves Risk',
        'All forms of trading and investing in securities markets — '
            'equities, futures, options, and commodities — involve '
            'substantial risk of loss and are not suitable for all '
            'investors. Before trading with real money, you should '
            'independently evaluate your financial situation and risk '
            'tolerance.',
      ),
      LegalSection(
        '7. Consult a Registered Advisor',
        'Before making any real investment or trading decision, please '
            'consult a SEBI-registered investment adviser or stockbroker who '
            'can assess your individual financial circumstances. '
            '$_kCompany strongly discourages using outcomes from this '
            'Platform as the sole basis for any real financial decision.',
      ),
      LegalSection(
        '8. Third-Party Data',
        'Market data displayed on the Platform is sourced from third-party '
            'providers for simulation purposes and may be delayed or differ '
            'slightly from live exchange feeds. We do not warrant its '
            'completeness or accuracy for any real-world use.',
      ),
    ],
  ),

  'risk-disclosure': LegalDoc(
    slug: 'risk-disclosure',
    title: 'Risk Disclosure',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. Purpose of This Disclosure',
        'This Risk Disclosure is provided so users understand the '
            'limitations of a simulated trading environment and the risks '
            'inherent in real securities markets, should they choose to '
            'trade with real money elsewhere after learning on $_kCompany.',
      ),
      LegalSection(
        '2. General Market Risk',
        'Prices of equities, futures, options, and commodities can be '
            'highly volatile and are influenced by factors including '
            'company performance, macroeconomic conditions, regulatory '
            'changes, and market sentiment. Real trading can result in '
            'losses that exceed initial capital, particularly in leveraged '
            'instruments such as futures and options.',
      ),
      LegalSection(
        '3. Leverage and Derivatives Risk',
        'Futures and options trading involves leverage, which can '
            'magnify both gains and losses. A relatively small adverse '
            'price movement can result in a substantial loss of the amount '
            'invested, and in some cases losses can exceed the original '
            'margin deposited. These risks are simulated for educational '
            'purposes on $_kCompany, but the real-world consequences are '
            'financial and can be severe.',
      ),
      LegalSection(
        '4. No Guarantee Against Loss',
        'No trading strategy, technical indicator, or educational course — '
            'whether taught or practiced on $_kCompany — can guarantee '
            'profits or protect against losses in live markets.',
      ),
      LegalSection(
        '5. Simulation Limitations',
        'Our paper trading engine estimates order execution, slippage, and '
            'margin using simplified models that will not perfectly reflect '
            'live exchange conditions, liquidity, or broker-specific rules. '
            'Do not rely on simulated results as a guarantee of real-market '
            'performance.',
      ),
      LegalSection(
        '6. Your Responsibility',
        'If you decide to trade with real money through a SEBI-registered '
            'broker, you do so entirely at your own risk and discretion. '
            '$_kCompany bears no responsibility for any real financial '
            'losses arising from decisions influenced by use of this '
            'Platform.',
      ),
    ],
  ),

  'cookie-policy': LegalDoc(
    slug: 'cookie-policy',
    title: 'Cookie Policy',
    lastUpdated: _kLastUpdated,
    sections: [
      LegalSection(
        '1. What Are Cookies',
        'Cookies are small text files stored on your device by your '
            'browser. $_kCompany uses cookies and similar technologies '
            '(such as local storage) to make the Platform work reliably and '
            'to understand how it is used.',
      ),
      LegalSection(
        '2. Types of Cookies We Use',
        'Strictly necessary cookies: required for core functionality such '
            'as keeping you signed in and maintaining session security. '
            'Preference cookies: remember settings like theme (light/dark) '
            'and layout. Analytics cookies: help us understand aggregate '
            'usage patterns so we can improve the Platform. We do not use '
            'cookies for third-party advertising.',
      ),
      LegalSection(
        '3. Managing Cookies',
        'Most browsers let you block or delete cookies through their '
            'settings. Blocking strictly necessary cookies may prevent you '
            'from signing in or using core features of the Platform.',
      ),
      LegalSection(
        '4. Changes to This Policy',
        'We may update this Cookie Policy from time to time; the "Last '
            'updated" date at the top reflects the most recent revision.',
      ),
      LegalSection(
        '5. Contact',
        'Questions about our use of cookies can be sent to $_kSupportEmail.',
      ),
    ],
  ),
};
