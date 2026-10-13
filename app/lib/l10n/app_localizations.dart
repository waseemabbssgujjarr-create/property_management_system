import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur')
  ];

  /// App name
  ///
  /// In ur, this message translates to:
  /// **'منشی'**
  String get appName;

  /// Tagline shown on splash
  ///
  /// In ur, this message translates to:
  /// **'آپ کا ڈیجیٹل منشی'**
  String get appTagline;

  /// No description provided for @loading.
  ///
  /// In ur, this message translates to:
  /// **'لوڈ ہو رہا ہے...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In ur, this message translates to:
  /// **'خرابی'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In ur, this message translates to:
  /// **'دوبارہ کوشش'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In ur, this message translates to:
  /// **'منسوخ'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In ur, this message translates to:
  /// **'تصدیق'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In ur, this message translates to:
  /// **'محفوظ کریں'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In ur, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ur, this message translates to:
  /// **'ترمیم'**
  String get edit;

  /// No description provided for @done.
  ///
  /// In ur, this message translates to:
  /// **'ہو گیا'**
  String get done;

  /// No description provided for @back.
  ///
  /// In ur, this message translates to:
  /// **'واپس'**
  String get back;

  /// No description provided for @next.
  ///
  /// In ur, this message translates to:
  /// **'اگلا'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In ur, this message translates to:
  /// **'مکمل'**
  String get finish;

  /// No description provided for @skip.
  ///
  /// In ur, this message translates to:
  /// **'چھوڑیں'**
  String get skip;

  /// No description provided for @yes.
  ///
  /// In ur, this message translates to:
  /// **'ہاں'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In ur, this message translates to:
  /// **'نہیں'**
  String get no;

  /// No description provided for @saveSuccess.
  ///
  /// In ur, this message translates to:
  /// **'محفوظ ہو گیا ✓'**
  String get saveSuccess;

  /// No description provided for @saveFailed.
  ///
  /// In ur, this message translates to:
  /// **'محفوظ نہیں ہوا'**
  String get saveFailed;

  /// No description provided for @syncInProgress.
  ///
  /// In ur, this message translates to:
  /// **'سیو ہو رہا ہے...'**
  String get syncInProgress;

  /// No description provided for @syncDone.
  ///
  /// In ur, this message translates to:
  /// **'ہو گیا'**
  String get syncDone;

  /// No description provided for @syncFailed.
  ///
  /// In ur, this message translates to:
  /// **'سیو نہیں ہوا'**
  String get syncFailed;

  /// No description provided for @retrySync.
  ///
  /// In ur, this message translates to:
  /// **'دوبارہ کوشش کریں'**
  String get retrySync;

  /// No description provided for @navHome.
  ///
  /// In ur, this message translates to:
  /// **'گھر'**
  String get navHome;

  /// No description provided for @navDeals.
  ///
  /// In ur, this message translates to:
  /// **'ڈیلز'**
  String get navDeals;

  /// No description provided for @navInventory.
  ///
  /// In ur, this message translates to:
  /// **'پراپرٹی'**
  String get navInventory;

  /// No description provided for @navParties.
  ///
  /// In ur, this message translates to:
  /// **'کلائنٹ'**
  String get navParties;

  /// No description provided for @navMore.
  ///
  /// In ur, this message translates to:
  /// **'مزید'**
  String get navMore;

  /// No description provided for @homeTitleSimple.
  ///
  /// In ur, this message translates to:
  /// **'آج کا حساب'**
  String get homeTitleSimple;

  /// No description provided for @homeCommissionExpected.
  ///
  /// In ur, this message translates to:
  /// **'توقع کمیشن'**
  String get homeCommissionExpected;

  /// No description provided for @homeCommissionReceived.
  ///
  /// In ur, this message translates to:
  /// **'موصول کمیشن'**
  String get homeCommissionReceived;

  /// No description provided for @homeTokensExpiring.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن ختم ہونے والے'**
  String get homeTokensExpiring;

  /// No description provided for @homeFollowupsDue.
  ///
  /// In ur, this message translates to:
  /// **'آج کے فالو اپ'**
  String get homeFollowupsDue;

  /// Money in — home button
  ///
  /// In ur, this message translates to:
  /// **'پیسہ آیا'**
  String get paisaAya;

  /// Money out — home button
  ///
  /// In ur, this message translates to:
  /// **'پیسہ گیا'**
  String get paisaGaya;

  /// New deal — home button
  ///
  /// In ur, this message translates to:
  /// **'نیا ڈیل'**
  String get nayaDeal;

  /// No description provided for @callKaro.
  ///
  /// In ur, this message translates to:
  /// **'کال کرو'**
  String get callKaro;

  /// No description provided for @whatsappKaro.
  ///
  /// In ur, this message translates to:
  /// **'واٹس ایپ کرو'**
  String get whatsappKaro;

  /// No description provided for @photoLo.
  ///
  /// In ur, this message translates to:
  /// **'فوٹو لو'**
  String get photoLo;

  /// No description provided for @bolo.
  ///
  /// In ur, this message translates to:
  /// **'بولو'**
  String get bolo;

  /// No description provided for @suno.
  ///
  /// In ur, this message translates to:
  /// **'سنو'**
  String get suno;

  /// No description provided for @hoGaya.
  ///
  /// In ur, this message translates to:
  /// **'ہو گیا'**
  String get hoGaya;

  /// No description provided for @reminder.
  ///
  /// In ur, this message translates to:
  /// **'یاد دہانی'**
  String get reminder;

  /// No description provided for @stageInquiry.
  ///
  /// In ur, this message translates to:
  /// **'انکوائری'**
  String get stageInquiry;

  /// No description provided for @stageToken.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن'**
  String get stageToken;

  /// No description provided for @stageBayana.
  ///
  /// In ur, this message translates to:
  /// **'بیعانہ'**
  String get stageBayana;

  /// No description provided for @stageRegistry.
  ///
  /// In ur, this message translates to:
  /// **'رجسٹری'**
  String get stageRegistry;

  /// No description provided for @stageClosed.
  ///
  /// In ur, this message translates to:
  /// **'مکمل'**
  String get stageClosed;

  /// No description provided for @stageLost.
  ///
  /// In ur, this message translates to:
  /// **'ختم'**
  String get stageLost;

  /// No description provided for @tokenConditional.
  ///
  /// In ur, this message translates to:
  /// **'مشروط ٹوکن'**
  String get tokenConditional;

  /// No description provided for @tokenConfirmed.
  ///
  /// In ur, this message translates to:
  /// **'پکا ٹوکن'**
  String get tokenConfirmed;

  /// No description provided for @dealPipeline.
  ///
  /// In ur, this message translates to:
  /// **'ڈیل پائپ لائن'**
  String get dealPipeline;

  /// No description provided for @dealPrice.
  ///
  /// In ur, this message translates to:
  /// **'ڈیل قیمت'**
  String get dealPrice;

  /// No description provided for @dealCommission.
  ///
  /// In ur, this message translates to:
  /// **'کمیشن'**
  String get dealCommission;

  /// No description provided for @dealCommissionExpected.
  ///
  /// In ur, this message translates to:
  /// **'متوقع کمیشن'**
  String get dealCommissionExpected;

  /// No description provided for @dealBuyer.
  ///
  /// In ur, this message translates to:
  /// **'خریدار'**
  String get dealBuyer;

  /// No description provided for @dealSeller.
  ///
  /// In ur, this message translates to:
  /// **'فروخت کنندہ'**
  String get dealSeller;

  /// No description provided for @dealProperty.
  ///
  /// In ur, this message translates to:
  /// **'پراپرٹی'**
  String get dealProperty;

  /// No description provided for @dealTokenAmount.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن رقم'**
  String get dealTokenAmount;

  /// No description provided for @dealTokenExpiry.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن کی آخری تاریخ'**
  String get dealTokenExpiry;

  /// No description provided for @dealBayanaAmount.
  ///
  /// In ur, this message translates to:
  /// **'بیعانہ رقم'**
  String get dealBayanaAmount;

  /// No description provided for @dealBayanaDue.
  ///
  /// In ur, this message translates to:
  /// **'بیعانہ کی تاریخ'**
  String get dealBayanaDue;

  /// No description provided for @propertyPlot.
  ///
  /// In ur, this message translates to:
  /// **'پلاٹ'**
  String get propertyPlot;

  /// No description provided for @propertyFile.
  ///
  /// In ur, this message translates to:
  /// **'فائل'**
  String get propertyFile;

  /// No description provided for @propertyHouse.
  ///
  /// In ur, this message translates to:
  /// **'گھر'**
  String get propertyHouse;

  /// No description provided for @propertyShop.
  ///
  /// In ur, this message translates to:
  /// **'دکان'**
  String get propertyShop;

  /// No description provided for @propertyCommercial.
  ///
  /// In ur, this message translates to:
  /// **'کمرشل'**
  String get propertyCommercial;

  /// No description provided for @propertyApartment.
  ///
  /// In ur, this message translates to:
  /// **'اپارٹمنٹ'**
  String get propertyApartment;

  /// No description provided for @propertySociety.
  ///
  /// In ur, this message translates to:
  /// **'سوسائٹی'**
  String get propertySociety;

  /// No description provided for @propertyBlock.
  ///
  /// In ur, this message translates to:
  /// **'بلاک'**
  String get propertyBlock;

  /// No description provided for @propertySize.
  ///
  /// In ur, this message translates to:
  /// **'سائز'**
  String get propertySize;

  /// No description provided for @propertyDemand.
  ///
  /// In ur, this message translates to:
  /// **'مانگ'**
  String get propertyDemand;

  /// No description provided for @propertyStatus.
  ///
  /// In ur, this message translates to:
  /// **'حیثیت'**
  String get propertyStatus;

  /// No description provided for @propertyStatusAvailable.
  ///
  /// In ur, this message translates to:
  /// **'دستیاب'**
  String get propertyStatusAvailable;

  /// No description provided for @propertyStatusTokenGiven.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن دیا'**
  String get propertyStatusTokenGiven;

  /// No description provided for @propertyStatusBayanaDone.
  ///
  /// In ur, this message translates to:
  /// **'بیعانہ ہوا'**
  String get propertyStatusBayanaDone;

  /// No description provided for @propertyStatusSold.
  ///
  /// In ur, this message translates to:
  /// **'فروخت'**
  String get propertyStatusSold;

  /// No description provided for @propertyStatusWithdrawn.
  ///
  /// In ur, this message translates to:
  /// **'واپس'**
  String get propertyStatusWithdrawn;

  /// No description provided for @partyBuyer.
  ///
  /// In ur, this message translates to:
  /// **'خریدار'**
  String get partyBuyer;

  /// No description provided for @partySeller.
  ///
  /// In ur, this message translates to:
  /// **'فروخت کنندہ'**
  String get partySeller;

  /// No description provided for @partyInvestor.
  ///
  /// In ur, this message translates to:
  /// **'سرمایہ کار'**
  String get partyInvestor;

  /// No description provided for @partyName.
  ///
  /// In ur, this message translates to:
  /// **'نام'**
  String get partyName;

  /// No description provided for @partyPhone.
  ///
  /// In ur, this message translates to:
  /// **'فون'**
  String get partyPhone;

  /// No description provided for @partyCnic.
  ///
  /// In ur, this message translates to:
  /// **'شناختی کارڈ'**
  String get partyCnic;

  /// No description provided for @partySource.
  ///
  /// In ur, this message translates to:
  /// **'ذریعہ'**
  String get partySource;

  /// No description provided for @partySourceWalkin.
  ///
  /// In ur, this message translates to:
  /// **'براہ راست'**
  String get partySourceWalkin;

  /// No description provided for @partySourceZameen.
  ///
  /// In ur, this message translates to:
  /// **'زمین ڈاٹ کام'**
  String get partySourceZameen;

  /// No description provided for @partySourceFacebook.
  ///
  /// In ur, this message translates to:
  /// **'فیس بک'**
  String get partySourceFacebook;

  /// No description provided for @partySourceReferral.
  ///
  /// In ur, this message translates to:
  /// **'سفارش'**
  String get partySourceReferral;

  /// No description provided for @partySourceOther.
  ///
  /// In ur, this message translates to:
  /// **'دیگر'**
  String get partySourceOther;

  /// No description provided for @partyWaOptIn.
  ///
  /// In ur, this message translates to:
  /// **'واٹس ایپ اجازت'**
  String get partyWaOptIn;

  /// No description provided for @paymentKindTokenIn.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن موصول'**
  String get paymentKindTokenIn;

  /// No description provided for @paymentKindBayanaIn.
  ///
  /// In ur, this message translates to:
  /// **'بیعانہ موصول'**
  String get paymentKindBayanaIn;

  /// No description provided for @paymentKindCommissionIn.
  ///
  /// In ur, this message translates to:
  /// **'کمیشن موصول'**
  String get paymentKindCommissionIn;

  /// No description provided for @paymentKindSplitPaid.
  ///
  /// In ur, this message translates to:
  /// **'حصہ ادا'**
  String get paymentKindSplitPaid;

  /// No description provided for @paymentKindExpense.
  ///
  /// In ur, this message translates to:
  /// **'خرچہ'**
  String get paymentKindExpense;

  /// No description provided for @paymentKindOtherIn.
  ///
  /// In ur, this message translates to:
  /// **'آمدنی'**
  String get paymentKindOtherIn;

  /// No description provided for @paymentKindOtherOut.
  ///
  /// In ur, this message translates to:
  /// **'ادائیگی'**
  String get paymentKindOtherOut;

  /// No description provided for @methodCash.
  ///
  /// In ur, this message translates to:
  /// **'نقد'**
  String get methodCash;

  /// No description provided for @methodBank.
  ///
  /// In ur, this message translates to:
  /// **'بینک'**
  String get methodBank;

  /// No description provided for @methodJazzcash.
  ///
  /// In ur, this message translates to:
  /// **'جاز کیش'**
  String get methodJazzcash;

  /// No description provided for @methodEasypaisa.
  ///
  /// In ur, this message translates to:
  /// **'ایزی پیسہ'**
  String get methodEasypaisa;

  /// No description provided for @receiptNumber.
  ///
  /// In ur, this message translates to:
  /// **'رسید نمبر'**
  String get receiptNumber;

  /// No description provided for @receiptDate.
  ///
  /// In ur, this message translates to:
  /// **'تاریخ'**
  String get receiptDate;

  /// No description provided for @receiptAmount.
  ///
  /// In ur, this message translates to:
  /// **'رقم'**
  String get receiptAmount;

  /// No description provided for @receiptGenerated.
  ///
  /// In ur, this message translates to:
  /// **'رسید تیار'**
  String get receiptGenerated;

  /// No description provided for @commissionBuyer.
  ///
  /// In ur, this message translates to:
  /// **'خریدار کمیشن'**
  String get commissionBuyer;

  /// No description provided for @commissionSeller.
  ///
  /// In ur, this message translates to:
  /// **'فروخت کنندہ کمیشن'**
  String get commissionSeller;

  /// No description provided for @commissionEarned.
  ///
  /// In ur, this message translates to:
  /// **'کمایا'**
  String get commissionEarned;

  /// No description provided for @commissionPaid.
  ///
  /// In ur, this message translates to:
  /// **'ادا کیا'**
  String get commissionPaid;

  /// No description provided for @commissionPending.
  ///
  /// In ur, this message translates to:
  /// **'باقی'**
  String get commissionPending;

  /// No description provided for @staffName.
  ///
  /// In ur, this message translates to:
  /// **'نام'**
  String get staffName;

  /// No description provided for @staffRole.
  ///
  /// In ur, this message translates to:
  /// **'عہدہ'**
  String get staffRole;

  /// No description provided for @staffShare.
  ///
  /// In ur, this message translates to:
  /// **'حصہ'**
  String get staffShare;

  /// No description provided for @staffEarned.
  ///
  /// In ur, this message translates to:
  /// **'بنا'**
  String get staffEarned;

  /// No description provided for @staffPaid.
  ///
  /// In ur, this message translates to:
  /// **'ملا'**
  String get staffPaid;

  /// No description provided for @staffPending.
  ///
  /// In ur, this message translates to:
  /// **'باقی'**
  String get staffPending;

  /// No description provided for @expenseCategoryOffice.
  ///
  /// In ur, this message translates to:
  /// **'دفتر'**
  String get expenseCategoryOffice;

  /// No description provided for @expenseCategoryFuel.
  ///
  /// In ur, this message translates to:
  /// **'تیل'**
  String get expenseCategoryFuel;

  /// No description provided for @expenseCategoryFood.
  ///
  /// In ur, this message translates to:
  /// **'کھانا'**
  String get expenseCategoryFood;

  /// No description provided for @expenseCategoryListingFee.
  ///
  /// In ur, this message translates to:
  /// **'اشتہار فیس'**
  String get expenseCategoryListingFee;

  /// No description provided for @expenseCategorySalary.
  ///
  /// In ur, this message translates to:
  /// **'تنخواہ'**
  String get expenseCategorySalary;

  /// No description provided for @expenseCategoryOther.
  ///
  /// In ur, this message translates to:
  /// **'دیگر'**
  String get expenseCategoryOther;

  /// No description provided for @followupDueToday.
  ///
  /// In ur, this message translates to:
  /// **'آج کے فالو اپ'**
  String get followupDueToday;

  /// No description provided for @followupOverdue.
  ///
  /// In ur, this message translates to:
  /// **'پرانے فالو اپ'**
  String get followupOverdue;

  /// No description provided for @followupNoItems.
  ///
  /// In ur, this message translates to:
  /// **'آج کوئی فالو اپ نہیں'**
  String get followupNoItems;

  /// No description provided for @searchHint.
  ///
  /// In ur, this message translates to:
  /// **'تلاش کریں'**
  String get searchHint;

  /// No description provided for @searchVoiceHint.
  ///
  /// In ur, this message translates to:
  /// **'بول کر تلاش کریں'**
  String get searchVoiceHint;

  /// No description provided for @notificationTokenExpiring.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن جلد ختم ہو گا'**
  String get notificationTokenExpiring;

  /// No description provided for @notificationBayanaDue.
  ///
  /// In ur, this message translates to:
  /// **'بیعانہ کی تاریخ قریب ہے'**
  String get notificationBayanaDue;

  /// No description provided for @notificationFollowupDue.
  ///
  /// In ur, this message translates to:
  /// **'فالو اپ باقی ہے'**
  String get notificationFollowupDue;

  /// No description provided for @notificationPaymentReceived.
  ///
  /// In ur, this message translates to:
  /// **'ادائیگی موصول'**
  String get notificationPaymentReceived;

  /// No description provided for @notificationCommissionReceived.
  ///
  /// In ur, this message translates to:
  /// **'کمیشن موصول'**
  String get notificationCommissionReceived;

  /// No description provided for @settingsLanguage.
  ///
  /// In ur, this message translates to:
  /// **'زبان'**
  String get settingsLanguage;

  /// No description provided for @settingsMode.
  ///
  /// In ur, this message translates to:
  /// **'موڈ'**
  String get settingsMode;

  /// No description provided for @settingsModeSimple.
  ///
  /// In ur, this message translates to:
  /// **'سادہ'**
  String get settingsModeSimple;

  /// No description provided for @settingsModeDetail.
  ///
  /// In ur, this message translates to:
  /// **'تفصیل'**
  String get settingsModeDetail;

  /// No description provided for @settingsVoice.
  ///
  /// In ur, this message translates to:
  /// **'آواز'**
  String get settingsVoice;

  /// No description provided for @settingsVoiceOn.
  ///
  /// In ur, this message translates to:
  /// **'آواز آن'**
  String get settingsVoiceOn;

  /// No description provided for @settingsVoiceOff.
  ///
  /// In ur, this message translates to:
  /// **'آواز آف'**
  String get settingsVoiceOff;

  /// No description provided for @settingsExport.
  ///
  /// In ur, this message translates to:
  /// **'ڈیٹا نکالیں'**
  String get settingsExport;

  /// No description provided for @settingsSubscription.
  ///
  /// In ur, this message translates to:
  /// **'سبسکرپشن'**
  String get settingsSubscription;

  /// No description provided for @settingsLogout.
  ///
  /// In ur, this message translates to:
  /// **'لاگ آوٹ'**
  String get settingsLogout;

  /// No description provided for @planStarter.
  ///
  /// In ur, this message translates to:
  /// **'اسٹارٹر'**
  String get planStarter;

  /// No description provided for @planPro.
  ///
  /// In ur, this message translates to:
  /// **'پرو'**
  String get planPro;

  /// No description provided for @planMonthly.
  ///
  /// In ur, this message translates to:
  /// **'ماہانہ'**
  String get planMonthly;

  /// No description provided for @planAnnual.
  ///
  /// In ur, this message translates to:
  /// **'سالانہ'**
  String get planAnnual;

  /// No description provided for @otpTitle.
  ///
  /// In ur, this message translates to:
  /// **'کوڈ درج کریں'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In ur, this message translates to:
  /// **'آپ کے نمبر پر بھیجا گیا'**
  String get otpSubtitle;

  /// No description provided for @otpResend.
  ///
  /// In ur, this message translates to:
  /// **'دوبارہ بھیجیں'**
  String get otpResend;

  /// No description provided for @otpVoiceOption.
  ///
  /// In ur, this message translates to:
  /// **'آواز سے کوڈ لیں'**
  String get otpVoiceOption;

  /// No description provided for @otpVerifying.
  ///
  /// In ur, this message translates to:
  /// **'تصدیق ہو رہی ہے...'**
  String get otpVerifying;

  /// No description provided for @otpInvalid.
  ///
  /// In ur, this message translates to:
  /// **'کوڈ درست نہیں'**
  String get otpInvalid;

  /// No description provided for @onboardingAgencyName.
  ///
  /// In ur, this message translates to:
  /// **'ایجنسی کا نام'**
  String get onboardingAgencyName;

  /// No description provided for @onboardingCity.
  ///
  /// In ur, this message translates to:
  /// **'شہر'**
  String get onboardingCity;

  /// No description provided for @onboardingAreas.
  ///
  /// In ur, this message translates to:
  /// **'علاقے'**
  String get onboardingAreas;

  /// No description provided for @onboardingTeamSize.
  ///
  /// In ur, this message translates to:
  /// **'ٹیم'**
  String get onboardingTeamSize;

  /// No description provided for @emptyDeals.
  ///
  /// In ur, this message translates to:
  /// **'کوئی ڈیل نہیں'**
  String get emptyDeals;

  /// No description provided for @emptyDealsHint.
  ///
  /// In ur, this message translates to:
  /// **'نیا ڈیل شروع کریں'**
  String get emptyDealsHint;

  /// No description provided for @emptyInventory.
  ///
  /// In ur, this message translates to:
  /// **'کوئی پراپرٹی نہیں'**
  String get emptyInventory;

  /// No description provided for @emptyInventoryHint.
  ///
  /// In ur, this message translates to:
  /// **'پراپرٹی شامل کریں'**
  String get emptyInventoryHint;

  /// No description provided for @emptyParties.
  ///
  /// In ur, this message translates to:
  /// **'کوئی کلائنٹ نہیں'**
  String get emptyParties;

  /// No description provided for @emptyPartiesHint.
  ///
  /// In ur, this message translates to:
  /// **'کلائنٹ شامل کریں'**
  String get emptyPartiesHint;

  /// No description provided for @emptyFollowups.
  ///
  /// In ur, this message translates to:
  /// **'آج کوئی کام نہیں'**
  String get emptyFollowups;

  /// No description provided for @errorGeneric.
  ///
  /// In ur, this message translates to:
  /// **'کچھ غلط ہوا'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In ur, this message translates to:
  /// **'انٹرنیٹ نہیں'**
  String get errorNetwork;

  /// No description provided for @errorNetworkOffline.
  ///
  /// In ur, this message translates to:
  /// **'آپ آف لائن ہیں'**
  String get errorNetworkOffline;

  /// No description provided for @errorPermission.
  ///
  /// In ur, this message translates to:
  /// **'اجازت نہیں'**
  String get errorPermission;

  /// No description provided for @errorNotFound.
  ///
  /// In ur, this message translates to:
  /// **'نہیں ملا'**
  String get errorNotFound;

  /// No description provided for @errorSaveFailed.
  ///
  /// In ur, this message translates to:
  /// **'محفوظ نہیں ہوا'**
  String get errorSaveFailed;

  /// No description provided for @voiceConfirmTokenReceived.
  ///
  /// In ur, this message translates to:
  /// **'ٹوکن موصول ہو گیا'**
  String get voiceConfirmTokenReceived;

  /// No description provided for @voiceConfirmPaymentReceived.
  ///
  /// In ur, this message translates to:
  /// **'ادائیگی موصول ہو گئی'**
  String get voiceConfirmPaymentReceived;

  /// No description provided for @voiceConfirmSaved.
  ///
  /// In ur, this message translates to:
  /// **'محفوظ ہو گیا'**
  String get voiceConfirmSaved;

  /// No description provided for @voiceConfirmDealCreated.
  ///
  /// In ur, this message translates to:
  /// **'نیا ڈیل بنا'**
  String get voiceConfirmDealCreated;

  /// No description provided for @lacUnit.
  ///
  /// In ur, this message translates to:
  /// **'لاکھ'**
  String get lacUnit;

  /// No description provided for @croreUnit.
  ///
  /// In ur, this message translates to:
  /// **'کروڑ'**
  String get croreUnit;

  /// No description provided for @rupeeSymbol.
  ///
  /// In ur, this message translates to:
  /// **'₨'**
  String get rupeeSymbol;

  /// No description provided for @importTitle.
  ///
  /// In ur, this message translates to:
  /// **'ڈیٹا درآمد'**
  String get importTitle;

  /// No description provided for @importSelectFile.
  ///
  /// In ur, this message translates to:
  /// **'فائل منتخب کریں'**
  String get importSelectFile;

  /// No description provided for @importPreview.
  ///
  /// In ur, this message translates to:
  /// **'پیش نظارہ'**
  String get importPreview;

  /// No description provided for @importConfirm.
  ///
  /// In ur, this message translates to:
  /// **'درآمد کریں'**
  String get importConfirm;

  /// No description provided for @importSuccess.
  ///
  /// In ur, this message translates to:
  /// **'{count} ریکارڈ درآمد ہوئے'**
  String importSuccess(int count);

  /// No description provided for @auditLog.
  ///
  /// In ur, this message translates to:
  /// **'تبدیلیوں کا ریکارڈ'**
  String get auditLog;

  /// No description provided for @helpVideos.
  ///
  /// In ur, this message translates to:
  /// **'مدد'**
  String get helpVideos;

  /// No description provided for @helpWatchVideo.
  ///
  /// In ur, this message translates to:
  /// **'دیکھیں کیسے ہوتا ہے'**
  String get helpWatchVideo;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
