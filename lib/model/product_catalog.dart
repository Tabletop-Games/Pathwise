const themePassProduct = 'pathwise_themes_forever';
const removeAdsProduct = 'pathwise_remove_ads';
const premiumProduct = 'pathwise_premium';

const storeProducts = {
  'pathwise_coins_120': (label: '120 coins', coins: 120, legacy: true),
  'pathwise_coins_340': (label: '340 coins', coins: 340, legacy: true),
  'pathwise_coins_800': (label: '800 coins', coins: 800, legacy: true),
  'pathwise_coins_500': (
    label: 'Starter · 500 coins',
    coins: 500,
    legacy: false,
  ),
  'pathwise_coins_1200': (
    label: 'Small · 1,200 coins',
    coins: 1200,
    legacy: false,
  ),
  'pathwise_coins_3500': (
    label: 'Medium · 3,500 coins',
    coins: 3500,
    legacy: false,
  ),
  'pathwise_coins_8000': (
    label: 'Large · 8,000 coins',
    coins: 8000,
    legacy: false,
  ),
  'pathwise_coins_20000': (
    label: 'Mega · 20,000 coins',
    coins: 20000,
    legacy: false,
  ),
  themePassProduct: (label: 'All themes forever', coins: 0, legacy: false),
  removeAdsProduct: (label: 'Remove Ads', coins: 0, legacy: false),
  premiumProduct: (label: 'Pathwise Premium', coins: 0, legacy: false),
};

bool consumable(String product) => (storeProducts[product]?.coins ?? 0) > 0;
