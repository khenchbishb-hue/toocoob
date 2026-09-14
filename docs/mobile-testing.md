# Android / iOS шалгах заавар

## 2026-09-15-ны шалгалтын дүн

- Android debug APK болон iOS Simulator build амжилттай гарсан.
- Android API 36.1 emulator, iPhone 16e / iOS 26.2 Simulator дээр
  үндсэн гурван smoke тест болон локал Firebase-тай нэвтрэх → тоглогч
  сонгох → покерын оноо оруулах → хадгалах бүрэн урсгал тэнцсэн.
- Нийт 76 unit/widget тест тэнцсэн. `flutter analyze` алдаагүй боловч
  төслийн 147 warning/info мэдэгдэл үлдсэн.
- iOS покерын түр дэлгэцийг үндсэн тоглоомтой холбож, жижиг дэлгэцийн
  самбар, тоглогчийн жагсаалт, онооны хэсэг, товчнуудын багтаамжийг зассан.

Бодит утас, production бүртгэл, хоёр төхөөрөмжийн cloud sync болон
App Store / Play Store release build энэ шалгалтад хамрагдаагүй.
Профайлын cloud хадгалалт дараагийн дутуу ажил хэвээр.

## Автомат шалгалт

```sh
flutter pub get
flutter test
flutter build apk --debug
flutter build ios --simulator
flutter devices
flutter test integration_test/mobile_smoke_test.dart -d <device-id>
```

Сүүлийн командыг Android emulator болон iOS Simulator тус бүрийн ID-тай
ажиллуулна. iOS build-д Mac, Xcode, CocoaPods шаардлагатай.

`test/mobile_layout_test.dart` нь утасны босоо/хэвтээ нэвтрэх дэлгэц,
нарийн дэлгэц дээр покерын оноо оруулах, хадгалах үйлдлийг шалгана.

`integration_test/mobile_smoke_test.dart` нь төхөөрөмж дээр Firebase
эхлүүлэх, нэвтрэх талбаруудад бичих, demo тоглогчтой покерт оноо оруулж
локал хадгалах, native SharedPreferences-ээс дахин уншихыг шалгана.
Синтетик нэвтрэх мэдээллийг сервер рүү илгээхгүй. Энэ нь баталгаажсан
хэрэглэгчээр нэвтрэх эсвэл Firestore sync-ийн бүрэн шалгалт биш.

## Локал Firebase-тай бүрэн урсгал

```sh
firebase emulators:start --only auth,firestore --project toocoob --config firebase.mobile-test.json
flutter test integration_test/mobile_login_game_test.dart -d <device-id>
```

Энэ тест Auth, Firestore, Functions endpoint-үүдийг зөвхөн локал хаягт
чиглүүлнэ. Auth/Firestore emulator дээр шинээр үүсгэсэн туршилтын
хэрэглэгчээр нэвтэрч, demo тоглогч сонгон покерын оноо хадгална.
Бодит Firebase үйлчилгээ болон бодит хэрэглэгчийн нууц үгийг ашиглахгүй.
Эмуляторын өгөгдлийг production руу экспортлох, deploy хийх шаардлагагүй.

Firebase-ийн [Authentication emulator заавар](https://firebase.google.com/docs/emulator-suite/connect_auth).

## Жинхэнэ бүртгэлтэй шалгах урсгал

1. Тусгай туршилтын бүртгэлээр төхөөрөмж дээр өөрөө нэвтэрнэ.
   Нууц үгийг код, командын аргумент, логт оруулахгүй.
2. Профайл ачаалж, тухайн бүртгэлийн тоглоом хөтлөх эрх зөв харагдана.
3. Тоглогчид, тоглолтын хэлбэр, тоглоомоо сонгоно.
4. Оноо оруулж, "Хадгалах" товч дарна.
5. Тоглоомоос гараад хадгалсан тоглолтыг нээж оноог тулгана.
6. Аппыг хааж дахин нээгээд хадгалсан тоглолт үлдсэн эсэхийг шалгана.
7. Хоёр төхөөрөмжийн live sync-ийг тусад нь шалгана.

Энэ шалгалтад хэрэглэсэн бүртгэл, тоглогч, ширээ нь туршилтын зориулалттай
байх ёстой. Профайлын cloud хадгалалтын дутуу ажлыг `PROJECT_NOTES.md`-д
тусад нь хөтөлнө.
