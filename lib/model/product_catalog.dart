const themePassProduct = 'pathwise_themes_forever';
const removeAdsProduct = 'pathwise_remove_ads';
const premiumProduct = 'pathwise_premium';

const storeProducts = {
  'pathwise_coins_500': (
    label: 'Starter · 500 coins',
    coins: 500),
  'pathwise_coins_1250': (
    label: 'Bronze · 1,250 coins',
    coins: 1250),
  'pathwise_coins_3000': (
    label: 'Silver · 3,000 coins',
    coins: 3000),
  'pathwise_coins_7500': (
    label: 'Gold · 7,500 coins',
    coins: 7500),
  'pathwise_coins_18000': (
    label: 'Diamond · 18,000 coins',
    coins: 18000),
  themePassProduct: (label: 'All themes forever', coins: 0),
  removeAdsProduct: (label: 'Remove Ads', coins: 0),
  premiumProduct: (label: 'Pathwise Premium', coins: 0),
};

bool consumable(String product) => (storeProducts[product]?.coins ?? 0) > 0;
