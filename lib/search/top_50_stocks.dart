// Top 50 NSE large-caps — loaded at app start, never fetched from network.
// Used for instant search (< 5ms) before the full instrument index is queried.

class Top50Stock {
  final String symbol;
  final String companyName;
  final String exchange;

  const Top50Stock({
    required this.symbol,
    required this.companyName,
    required this.exchange,
  });
}

const List<Top50Stock> kTop50Stocks = [
  Top50Stock(symbol: 'RELIANCE',   companyName: 'Reliance Industries',                   exchange: 'NSE'),
  Top50Stock(symbol: 'HDFCBANK',   companyName: 'HDFC Bank',                             exchange: 'NSE'),
  Top50Stock(symbol: 'ICICIBANK',  companyName: 'ICICI Bank',                            exchange: 'NSE'),
  Top50Stock(symbol: 'INFY',       companyName: 'Infosys',                               exchange: 'NSE'),
  Top50Stock(symbol: 'TCS',        companyName: 'Tata Consultancy Services',             exchange: 'NSE'),
  Top50Stock(symbol: 'BHARTIARTL', companyName: 'Bharti Airtel',                         exchange: 'NSE'),
  Top50Stock(symbol: 'SBIN',       companyName: 'State Bank of India',                   exchange: 'NSE'),
  Top50Stock(symbol: 'LT',         companyName: 'Larsen & Toubro',                       exchange: 'NSE'),
  Top50Stock(symbol: 'ITC',        companyName: 'ITC',                                   exchange: 'NSE'),
  Top50Stock(symbol: 'HINDUNILVR', companyName: 'Hindustan Unilever',                    exchange: 'NSE'),
  Top50Stock(symbol: 'AXISBANK',   companyName: 'Axis Bank',                             exchange: 'NSE'),
  Top50Stock(symbol: 'KOTAKBANK',  companyName: 'Kotak Mahindra Bank',                   exchange: 'NSE'),
  Top50Stock(symbol: 'M&M',        companyName: 'Mahindra & Mahindra',                   exchange: 'NSE'),
  Top50Stock(symbol: 'BAJFINANCE', companyName: 'Bajaj Finance',                         exchange: 'NSE'),
  Top50Stock(symbol: 'MARUTI',     companyName: 'Maruti Suzuki India',                   exchange: 'NSE'),
  Top50Stock(symbol: 'SUNPHARMA',  companyName: 'Sun Pharmaceutical Industries',         exchange: 'NSE'),
  Top50Stock(symbol: 'TITAN',      companyName: 'Titan Company',                         exchange: 'NSE'),
  Top50Stock(symbol: 'ULTRACEMCO', companyName: 'UltraTech Cement',                      exchange: 'NSE'),
  Top50Stock(symbol: 'NTPC',       companyName: 'NTPC',                                  exchange: 'NSE'),
  Top50Stock(symbol: 'POWERGRID',  companyName: 'Power Grid Corporation of India',       exchange: 'NSE'),
  Top50Stock(symbol: 'ASIANPAINT', companyName: 'Asian Paints',                          exchange: 'NSE'),
  Top50Stock(symbol: 'BAJAJFINSV', companyName: 'Bajaj Finserv',                         exchange: 'NSE'),
  Top50Stock(symbol: 'NESTLEIND',  companyName: 'Nestlé India',                          exchange: 'NSE'),
  Top50Stock(symbol: 'ADANIPORTS', companyName: 'Adani Ports and Special Economic Zone', exchange: 'NSE'),
  Top50Stock(symbol: 'HCLTECH',    companyName: 'HCL Technologies',                      exchange: 'NSE'),
  Top50Stock(symbol: 'WIPRO',      companyName: 'Wipro',                                 exchange: 'NSE'),
  Top50Stock(symbol: 'TECHM',      companyName: 'Tech Mahindra',                         exchange: 'NSE'),
  // Tata Motors demerged into TMPV (passenger vehicles) and TMCV
  // (commercial vehicles, continuing "Tata Motors Limited") in 2024.
  Top50Stock(symbol: 'TMCV',       companyName: 'Tata Motors',                           exchange: 'NSE'),
  Top50Stock(symbol: 'TATASTEEL',  companyName: 'Tata Steel',                            exchange: 'NSE'),
  Top50Stock(symbol: 'JSWSTEEL',   companyName: 'JSW Steel',                             exchange: 'NSE'),
  Top50Stock(symbol: 'INDUSINDBK', companyName: 'IndusInd Bank',                         exchange: 'NSE'),
  Top50Stock(symbol: 'DRREDDY',    companyName: "Dr. Reddy's Laboratories",              exchange: 'NSE'),
  Top50Stock(symbol: 'CIPLA',      companyName: 'Cipla',                                 exchange: 'NSE'),
  Top50Stock(symbol: 'APOLLOHOSP', companyName: 'Apollo Hospitals Enterprise',           exchange: 'NSE'),
  Top50Stock(symbol: 'GRASIM',     companyName: 'Grasim Industries',                     exchange: 'NSE'),
  Top50Stock(symbol: 'COALINDIA',  companyName: 'Coal India',                            exchange: 'NSE'),
  Top50Stock(symbol: 'BRITANNIA',  companyName: 'Britannia Industries',                  exchange: 'NSE'),
  Top50Stock(symbol: 'EICHERMOT',  companyName: 'Eicher Motors',                         exchange: 'NSE'),
  Top50Stock(symbol: 'SHRIRAMFIN', companyName: 'Shriram Finance',                       exchange: 'NSE'),
  Top50Stock(symbol: 'BEL',        companyName: 'Bharat Electronics',                    exchange: 'NSE'),
  Top50Stock(symbol: 'TRENT',      companyName: 'Trent',                                 exchange: 'NSE'),
  Top50Stock(symbol: 'HINDALCO',   companyName: 'Hindalco Industries',                   exchange: 'NSE'),
  Top50Stock(symbol: 'ONGC',       companyName: 'Oil and Natural Gas Corporation',       exchange: 'NSE'),
  Top50Stock(symbol: 'HEROMOTOCO', companyName: 'Hero MotoCorp',                         exchange: 'NSE'),
  Top50Stock(symbol: 'SBILIFE',    companyName: 'SBI Life Insurance',                    exchange: 'NSE'),
  Top50Stock(symbol: 'LTIM',       companyName: 'LTIMindtree',                           exchange: 'NSE'),
  Top50Stock(symbol: 'ADANIENT',   companyName: 'Adani Enterprises',                     exchange: 'NSE'),
  Top50Stock(symbol: 'JIOFIN',     companyName: 'Jio Financial Services',                exchange: 'NSE'),
  Top50Stock(symbol: 'BPCL',       companyName: 'Bharat Petroleum Corporation',          exchange: 'NSE'),
  Top50Stock(symbol: 'HDFCLIFE',   companyName: 'HDFC Life Insurance',                   exchange: 'NSE'),
];
