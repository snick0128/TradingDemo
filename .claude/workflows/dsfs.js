
export const meta = {
  name: 'platform-audit',
  description: 'Full audit of all P&L and financial calculations in the trading platform',
  phases: [
    { title: 'Read Files', detail: 'Read all financial calculation files in parallel' },
    { title: 'Analyse', detail: 'Identify every bug and inconsistency' },
  ],
};

phase('Read Files');

const BASE = '/Users/albertamac/Desktop/Box Trading';

const results = await parallel([
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/screens/portfolio_screen.dart and return every line of code verbatim.`, { label: 'portfolio_screen' }),
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/screens/trade_history_screen.dart and return every line of code verbatim.`, { label: 'trade_history_screen' }),
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/screens/wallet_screen.dart and return every line of code verbatim.`, { label: 'wallet_screen' }),
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/state/trading_scope.dart and return every line of code verbatim.`, { label: 'trading_scope' }),
  () => agent(`Read the COMPLETE file at ${BASE}/paper_trading_backend/src/routes/analyticsRoutes.js and return every line of code verbatim.`, { label: 'analyticsRoutes' }),
  () => agent(`Read the COMPLETE file at ${BASE}/paper_trading_backend/src/routes/userRoutes.js and return every line of code verbatim.`, { label: 'userRoutes' }),
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/state/trading_store.dart and return ALL lines from 400 to end of file verbatim.`, { label: 'trading_store_tail' }),
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/screens/admin/admin_users_screen.dart and search for every place that calculates or displays P&L, balance, equity, margin. Return the relevant code sections verbatim with line numbers.`, { label: 'admin_users_pnl' }),
  () => agent(`Read the COMPLETE file at ${BASE}/box_trading_web/lib/screens/admin/admin_dashboard_screen.dart and return ALL lines that compute or display any financial metric (P&L, balance, volume, revenue, equity). Return verbatim with line numbers.`, { label: 'admin_dashboard_pnl' }),
  () => agent(`Run this bash command and return the complete output: grep -n "pnl\\|PnL\\|gross\\|charges\\|brokerage\\|realized\\|unrealized\\|netPnl\\|runningPnl\\|balance\\|equity\\|margin" "/Users/albertamac/Desktop/Box Trading/box_trading_web/lib/screens/portfolio_screen.dart" | head -100`, { label: 'portfolio_grep' }),
]);

phase('Analyse');

const [
  portfolioFile,
  tradeHistoryFile,
  walletFile,
  tradingScope,
  analyticsRoutes,
  userRoutes,
  tradingStoreTail,
  adminUsersPnl,
  adminDashboard,
  portfolioGrep,
] = results;

const analysis = await agent(`
You are auditing a Flutter + Node.js paper trading platform for financial calculation inconsistencies.
The user reports these observed values that CANNOT all be correct simultaneously:
  - User Wallet: Balance ₹8,228.14 | Running P&L ₹0 | Available Margin ₹8,228.14
  - Admin Dashboard: Balance ₹8.2K | Overall P&L: -₹12.8K
  - Portfolio Screen: Net P&L Today -₹3,946.31 | Gross P&L ₹0 | Charges -₹3,946.31 | Winners 0 | Losers 13

Here is the source code for analysis:

=== PORTFOLIO SCREEN ===
${portfolioFile}

=== PORTFOLIO GREP (P&L references) ===
${portfolioGrep}

=== TRADE HISTORY SCREEN ===
${tradeHistoryFile}

=== WALLET SCREEN ===
${walletFile}

=== TRADING SCOPE (store getters) ===
${tradingScope}

=== TRADING STORE (bottom half) ===
${tradingStoreTail}

=== ADMIN DASHBOARD P&L ===
${adminDashboard}

=== ADMIN USERS P&L ===
${adminUsersPnl}

=== ANALYTICS ROUTES ===
${analyticsRoutes}

=== USER ROUTES (portfolio/positions) ===
${userRoutes}

For each bug found, give:
1. EXACT file path and line numbers
2. EXACT broken code
3. EXACT correct replacement code
4. Root cause explanation in 2 sentences
5. Which screens are affected

Focus on:
- Why Gross P&L = ₹0 while Net P&L Today = -₹3,946.31 (Charges = P&L is very suspicious)
- Why Running P&L = ₹0 in wallet when there are 13 losing trades
- Why Admin Dashboard P&L (-₹12.8K) differs from Portfolio (-₹3,946.31)
- FIFO quantity mismatch (buy 100 + buy 50 + sell 80 → should partially close, not leave full position open)
- Any screen that calculates P&L locally instead of using pnlEngine/backend values
- Missing fields in orders that cause calculations to fall back to wrong formulas
- Trade ledger showing OPEN when positions are actually closed

Be precise, exhaustive, and actionable.
`, { label: 'bug-analysis' });

return { analysis, portfolioFile, tradeHistoryFile, walletFile };
