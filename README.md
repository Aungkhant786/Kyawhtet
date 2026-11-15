# ကျော်ထက်အောင် ငါးရောင်းဝယ်ရေး - ဘောင်ချာ App (Flutter)

## လုပ်ဆောင်ချက်များ
- ရောင်း / ဝယ် ဘောင်ချာ နှစ်မျိုးထုတ်နိုင်
- ငါးအမည်၊ ပမာဏ (ပိဿာ/ကီလို/ကောင်/ခြင်း)၊ ဈေး ထည့်ပြီး စုစုပေါင်း အလိုအလျောက်တွက်
- ဘောင်ချာအမှတ် အလိုအလျောက်တိုး၊ ရက်စွဲရွေးနိုင်
- ဘောင်ချာကို ပုံအဖြစ် ပို့နိုင် (Viber/Messenger စသည်) နဲ့ Print / PDF
- ဘောင်ချာမှတ်တမ်း (ဖုန်းထဲမှာသိမ်း၊ ဖျက်ချင်ရင် ဖိထား)

## APK ထုတ်နည်း (၂ နည်း)

### နည်း ၁ - GitHub နဲ့ (ကွန်ပျူတာ မလို)
1. GitHub မှာ repository အသစ်ဖွင့်ပြီး ဒီ folder ထဲက ဖိုင်အားလုံး (`.github` ပါ) တင်ပါ
2. **Actions** tab → **Build APK** → **Run workflow**
3. ၅-၁၀ မိနစ်ကြာရင် ပြီးမယ်။ Run ထဲက **Artifacts → voucher-apk** ကို download လုပ်ပါ
4. ဖုန်းထဲထည့်ပြီး install လုပ်ပါ ("Unknown sources" ခွင့်ပြုရန်လို)

### နည်း ၂ - ကိုယ့်ကွန်ပျူတာမှာ
```
flutter create --org com.kyawhtetaung --project-name kyawhtetaung_voucher --platforms=android .
flutter pub get
flutter build apk --release
```
APK: `build/app/outputs/flutter-apk/app-release.apk`
