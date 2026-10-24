// Native bridge for the Android build. Bundled by esbuild into www/native.js and loaded
// before the game script. The game only talks to window.EchoNative; in a plain browser
// this file is never loaded and the game falls back to its demo ads and checkout.
import { Capacitor } from '@capacitor/core';
import { AdMob, RewardAdPluginEvents, InterstitialAdPluginEvents, AdmobConsentStatus } from '@capacitor-community/admob';
import { Haptics, ImpactStyle } from '@capacitor/haptics';
import { App } from '@capacitor/app';

// ---- configure before release ------------------------------------------------
// These are Google's public TEST ad units. Replace them with your own AdMob unit IDs
// (and set TESTING to false) for the production build. Never click your own live ads.
const TESTING = true;
const AD_UNITS = {
  rewarded: 'ca-app-pub-3940256099942544/5224354917',
  interstitial: 'ca-app-pub-3940256099942544/1033173712',
};
// Product IDs must match the in-app products you create in Play Console.
const NON_CONSUMABLE = ['no_ads', 'starter', 'skin_aurum', 'skin_spectrum'];
const CONSUMABLE = ['shards_s'];
// -------------------------------------------------------------------------------

const game = () => window.EchoLoop || {};

/* ---------------- ads ---------------- */
let adsReady = false, rewardedLoaded = false, interLoaded = false;

async function initAds() {
  try {
    const consent = await AdMob.requestConsentInfo();
    if (consent.isConsentFormAvailable && consent.status === AdmobConsentStatus.REQUIRED) await AdMob.showConsentForm();
    await AdMob.initialize({ initializeForTesting: TESTING });
    adsReady = true;
    preloadRewarded();
    preloadInterstitial();
  } catch (e) {
    console.warn('[ads] init failed', e);
  }
}
async function preloadRewarded() {
  try { await AdMob.prepareRewardVideoAd({ adId: AD_UNITS.rewarded, isTesting: TESTING }); rewardedLoaded = true; }
  catch (e) { rewardedLoaded = false; }
}
async function preloadInterstitial() {
  try { await AdMob.prepareInterstitial({ adId: AD_UNITS.interstitial, isTesting: TESTING }); interLoaded = true; }
  catch (e) { interLoaded = false; }
}

// Resolves true only if the player watched long enough to earn the reward.
async function showRewarded() {
  if (!adsReady) return false;
  if (!rewardedLoaded) { await preloadRewarded(); if (!rewardedLoaded) return false; }
  return new Promise(async resolve => {
    let earned = false, settled = false;
    const handles = [];
    const finish = () => {
      if (settled) return;
      settled = true;
      handles.forEach(h => h.remove());
      rewardedLoaded = false;
      preloadRewarded();
      resolve(earned);
    };
    handles.push(await AdMob.addListener(RewardAdPluginEvents.Rewarded, () => { earned = true; }));
    handles.push(await AdMob.addListener(RewardAdPluginEvents.Dismissed, finish));
    handles.push(await AdMob.addListener(RewardAdPluginEvents.FailedToShow, finish));
    try { await AdMob.showRewardVideoAd(); } catch (e) { finish(); }
  });
}

async function showInterstitial() {
  if (!adsReady || !interLoaded) { preloadInterstitial(); return; }
  await new Promise(async resolve => {
    let settled = false;
    const handles = [];
    const finish = () => {
      if (settled) return;
      settled = true;
      handles.forEach(h => h.remove());
      interLoaded = false;
      preloadInterstitial();
      resolve();
    };
    handles.push(await AdMob.addListener(InterstitialAdPluginEvents.Dismissed, finish));
    handles.push(await AdMob.addListener(InterstitialAdPluginEvents.FailedToShow, finish));
    try { await AdMob.showInterstitial(); } catch (e) { finish(); }
  });
}

/* ---------------- Google Play Billing (cordova-plugin-purchase) ---------------- */
let store = null;
const pending = new Map(); // sku -> resolve(boolean)

function initBilling() {
  const C = window.CdvPurchase;
  if (!C) { console.warn('[billing] plugin missing'); return; }
  store = C.store;
  const { ProductType, Platform } = C;
  store.register([
    ...NON_CONSUMABLE.map(id => ({ id, type: ProductType.NON_CONSUMABLE, platform: Platform.GOOGLE_PLAY })),
    ...CONSUMABLE.map(id => ({ id, type: ProductType.CONSUMABLE, platform: Platform.GOOGLE_PLAY })),
  ]);
  store.when()
    // For production, add server-side receipt validation (store.validator) and call
    // tx.verify() here instead of finishing straight away.
    .approved(tx => tx.finish())
    .finished(tx => {
      for (const p of tx.products) {
        const resolve = pending.get(p.id);
        if (resolve) { pending.delete(p.id); resolve(true); }
        else if (game().grantProduct) game().grantProduct(p.id, NON_CONSUMABLE.includes(p.id)); // purchase finished while the game wasn't waiting
      }
    })
    .receiptUpdated(() => {
      for (const id of NON_CONSUMABLE) if (store.owned(id) && game().grantProduct) game().grantProduct(id, true);
    })
    .productUpdated(() => {
      const prices = {};
      for (const id of [...NON_CONSUMABLE, ...CONSUMABLE]) {
        const p = store.get(id, Platform.GOOGLE_PLAY);
        if (p && p.pricing && p.pricing.price) prices[id] = p.pricing.price;
      }
      if (game().setPrices) game().setPrices(prices);
    });
  store.error(err => console.warn('[billing]', err && err.message));
  store.initialize([Platform.GOOGLE_PLAY]);
}

function purchase(sku) {
  return new Promise(resolve => {
    if (!store) return resolve(false);
    const p = store.get(sku, window.CdvPurchase.Platform.GOOGLE_PLAY);
    const offer = p && p.getOffer();
    if (!offer) return resolve(false);
    pending.set(sku, resolve);
    offer.order().then(err => {
      if (err) { pending.delete(sku); resolve(false); }
    });
  });
}

async function restore() {
  if (!store) return [];
  await store.restorePurchases();
  return NON_CONSUMABLE.filter(id => store.owned(id));
}

/* ---------------- haptics ---------------- */
function haptic(pattern) {
  const ms = Array.isArray(pattern) ? pattern.filter((_, i) => i % 2 === 0).reduce((a, b) => a + b, 0) : pattern;
  if (ms <= 12) Haptics.impact({ style: ImpactStyle.Light }).catch(() => {});
  else Haptics.vibrate({ duration: Math.min(ms, 300) }).catch(() => {});
}

/* ---------------- wire up ---------------- */
if (Capacitor.isNativePlatform()) {
  window.EchoNative = { showRewarded, showInterstitial, purchase, restore, haptic };
  App.addListener('backButton', () => {
    const handled = game().back ? game().back() : false;
    if (!handled) App.exitApp();
  });
  App.addListener('pause', () => { if (game().pause) game().pause(); });
  initAds();
  document.addEventListener('deviceready', initBilling, false);
}
