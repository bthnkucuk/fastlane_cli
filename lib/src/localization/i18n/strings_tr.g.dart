///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsTr = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.tr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <tr>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations

	/// tr: 'Ana Sayfa'
	String get homeTitle => 'Ana Sayfa';

	/// tr: 'Android'
	String get androidTitle => 'Android';

	/// tr: 'iOS'
	String get iosTitle => 'iOS';

	/// tr: 'Genel'
	String get generalTitle => 'Genel';

	/// tr: 'Kılavuz'
	String get guidesTitle => 'Kılavuz';

	/// tr: 'Çalıştır'
	String get runTitle => 'Çalıştır';

	/// tr: 'Hızlı Erişim'
	String get shortcuts => 'Hızlı Erişim';

	/// tr: 'Kategoriler'
	String get categories => 'Kategoriler';

	/// tr: 'Aksiyon bulunamadı.'
	String get noAction => 'Aksiyon bulunamadı.';

	/// tr: 'Enter: Çalıştır'
	String get pressEnterToRun => 'Enter: Çalıştır';

	/// tr: '↑/↓: Seçim değiştir'
	String get upDownNavigate => '↑/↓: Seçim değiştir';

	/// tr: 'A:Android I:iOS G:Genel H:Ana D:Guide L:Dil Q:Çıkış'
	String get footerHints => 'A:Android I:iOS G:Genel H:Ana D:Guide L:Dil Q:Çıkış';

	/// tr: 'Son Çalıştırma'
	String get lastRun => 'Son Çalıştırma';

	/// tr: 'Komut'
	String get command => 'Komut';

	/// tr: 'Loglar'
	String get logs => 'Loglar';

	/// tr: 'İlerleme'
	String get progress => 'İlerleme';

	/// tr: 'Aktif Dosya'
	String get currentFile => 'Aktif Dosya';

	/// tr: 'Log akışı bekleniyor...'
	String get waitingLogs => 'Log akışı bekleniyor...';

	/// tr: '/ sayfa veya aksiyon ara'
	String get commandPalettePlaceholder => '/ sayfa veya aksiyon ara';

	/// tr: 'Komut Paleti'
	String get commandPaletteTitle => 'Komut Paleti';

	/// tr: 'Eşleşme bulunamadı'
	String get commandPaletteNoResult => 'Eşleşme bulunamadı';

	/// tr: '⚡ Fast CLI'
	String get shellBrand => '⚡ Fast CLI';

	/// tr: 'Sayfalar'
	String get pages => 'Sayfalar';

	/// tr: 'Doğrulama başarısız'
	String get validationFailed => 'Doğrulama başarısız';

	/// tr: 'Aksiyon kılavuz eksikleri nedeniyle durduruldu.'
	String get blockedByGuide => 'Aksiyon kılavuz eksikleri nedeniyle durduruldu.';

	/// tr: 'Çalıştırma Onayı'
	String get runConfirmTitle => 'Çalıştırma Onayı';

	/// tr: '"${actionTitle}" aksiyonunu çalıştırmak istiyor musun?'
	String runConfirmMessage({required Object actionTitle}) => '"${actionTitle}" aksiyonunu çalıştırmak istiyor musun?';

	/// tr: 'Y/Enter: Onayla · N/Esc: İptal'
	String get runConfirmHint => 'Y/Enter: Onayla · N/Esc: İptal';

	/// tr: 'Onayla (Y/Enter)'
	String get runConfirmApprove => 'Onayla (Y/Enter)';

	/// tr: 'İptal (N/Esc)'
	String get runConfirmCancel => 'İptal (N/Esc)';

	/// tr: 'Çıkış Onayı'
	String get quitConfirmTitle => 'Çıkış Onayı';

	/// tr: 'Uygulamadan çıkmak istediğine emin misin?'
	String get quitConfirmMessage => 'Uygulamadan çıkmak istediğine emin misin?';

	/// tr: 'R: Tekrar dene'
	String get retry => 'R: Tekrar dene';

	/// tr: 'B: Geri'
	String get back => 'B: Geri';

	/// tr: 'C/Ctrl+Shift+C: Çıktıyı kopyala'
	String get copyOutput => 'C/Ctrl+Shift+C: Çıktıyı kopyala';

	/// tr: 'Çıktı panoya kopyalandı.'
	String get copiedOutput => 'Çıktı panoya kopyalandı.';

	/// tr: 'Bu aksiyon onay gerektirir. Y ile onayla.'
	String get confirmPrompt => 'Bu aksiyon onay gerektirir. Y ile onayla.';

	/// tr: 'R: Bu aksiyonu tekrar çalıştır'
	String get guideRetry => 'R: Bu aksiyonu tekrar çalıştır';

	/// tr: 'Bu konu için kılavuz yok.'
	String get guideFallback => 'Bu konu için kılavuz yok.';

	/// tr: 'Dry-run (simülasyon)'
	String get dryRunLabel => 'Dry-run (simülasyon)';

	/// tr: 'Dil'
	String get localeLabel => 'Dil';

	late final TranslationsPromptTr prompt = TranslationsPromptTr.internal(_root);
	late final TranslationsStatusTr status = TranslationsStatusTr.internal(_root);
	late final TranslationsPaletteTr palette = TranslationsPaletteTr.internal(_root);
	late final TranslationsGuidesTr guides = TranslationsGuidesTr.internal(_root);
}

// Path: prompt
class TranslationsPromptTr {
	TranslationsPromptTr.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// tr: 'İki faktörlü doğrulama kodu'
	String get twoFactorTitle => 'İki faktörlü doğrulama kodu';

	/// tr: '${digits} haneli kodu giriniz'
	String twoFactorBody({required Object digits}) => '${digits} haneli kodu giriniz';

	/// tr: '${digits} haneli kod'
	String twoFactorHint({required Object digits}) => '${digits} haneli kod';

	/// tr: 'Onay'
	String get yesNoTitle => 'Onay';

	/// tr: 'Lane evet/hayır yanıtı bekliyor.'
	String get yesNoBody => 'Lane evet/hayır yanıtı bekliyor.';

	/// tr: 'Bu bilgisayara güveniliyor mu?'
	String get trustComputerTitle => 'Bu bilgisayara güveniliyor mu?';

	/// tr: 'Apple, bu bilgisayara App Store Connect için güvenip güvenmediğini soruyor.'
	String get trustComputerBody => 'Apple, bu bilgisayara App Store Connect için güvenip güvenmediğini soruyor.';

	/// tr: 'Bir seçenek seçin'
	String get chooseIndexTitle => 'Bir seçenek seçin';

	/// tr: '${lo} ile ${hi} arasında bir sayı seçin'
	String chooseIndexBody({required Object lo, required Object hi}) => '${lo} ile ${hi} arasında bir sayı seçin';

	/// tr: 'Lane giriş bekliyor'
	String get freeFormTitle => 'Lane giriş bekliyor';

	/// tr: 'Gönder'
	String get submit => 'Gönder';

	/// tr: 'İptal'
	String get cancel => 'İptal';

	/// tr: 'Evet'
	String get yes => 'Evet';

	/// tr: 'Hayır'
	String get no => 'Hayır';

	/// tr: '${n} haneli olmalı'
	String errorWrongLength({required Object n}) => '${n} haneli olmalı';

	/// tr: 'Yalnızca rakam'
	String get errorOnlyDigits => 'Yalnızca rakam';

	/// tr: 'y/n giriniz'
	String get errorYesOrNo => 'y/n giriniz';

	/// tr: '${lo}-${hi} arası olmalı'
	String errorOutOfRange({required Object lo, required Object hi}) => '${lo}-${hi} arası olmalı';

	/// tr: 'Zorunlu'
	String get errorRequired => 'Zorunlu';
}

// Path: status
class TranslationsStatusTr {
	TranslationsStatusTr.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// tr: 'Bekleniyor'
	String get idle => 'Bekleniyor';

	/// tr: 'Doğrulanıyor'
	String get validating => 'Doğrulanıyor';

	/// tr: 'Bloklandı'
	String get blocked => 'Bloklandı';

	/// tr: 'Onay Bekliyor'
	String get confirmationRequired => 'Onay Bekliyor';

	/// tr: 'Çalışıyor'
	String get running => 'Çalışıyor';

	/// tr: 'Başarılı'
	String get succeeded => 'Başarılı';

	/// tr: 'Başarısız'
	String get failed => 'Başarısız';

	/// tr: 'Dry-run tamamlandı'
	String get dryRun => 'Dry-run tamamlandı';
}

// Path: palette
class TranslationsPaletteTr {
	TranslationsPaletteTr.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// tr: 'Ana Sayfa'
	String get homeTitle => 'Ana Sayfa';

	/// tr: 'Genel'
	String get generalTitle => 'Genel';

	/// tr: 'Guide: Android Metadata'
	String get guideAndroidMetadata => 'Guide: Android Metadata';

	/// tr: 'Guide: iOS Metadata'
	String get guideIosMetadata => 'Guide: iOS Metadata';

	/// tr: 'Çıkış'
	String get quitTitle => 'Çıkış';

	/// tr: 'q, quit, exit'
	String get quitSubtitle => 'q, quit, exit';
}

// Path: guides
class TranslationsGuidesTr {
	TranslationsGuidesTr.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsGuidesAndroidMetadataTr androidMetadata = TranslationsGuidesAndroidMetadataTr.internal(_root);
	late final TranslationsGuidesIosMetadataTr iosMetadata = TranslationsGuidesIosMetadataTr.internal(_root);
}

// Path: guides.androidMetadata
class TranslationsGuidesAndroidMetadataTr {
	TranslationsGuidesAndroidMetadataTr.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// tr: 'Android Metadata & Screenshots'
	String get title => 'Android Metadata & Screenshots';

	/// tr: 'Play Store metadata ve screenshot klasörlerini bu yapıda hazırlayın.'
	String get summary => 'Play Store metadata ve screenshot klasörlerini bu yapıda hazırlayın.';

	List<String> get checklist => [
		'Locale klasörü açın (ör. tr-TR, en-US).',
		'title.txt, short_description.txt, full_description.txt ekleyin.',
		'changelogs/<version_code>.txt ile release notes dosyası ekleyin.',
		'images altında tüm screenshot klasörlerini oluşturun.',
		'En az bir ekran görüntüsünü .png/.jpg olarak ekleyin.',
	];
	List<String> get pathSuffixes => [
		'/<locale>/title.txt',
		'/<locale>/short_description.txt',
		'/<locale>/full_description.txt',
		'/<locale>/changelogs/<version_code>.txt',
		'/<locale>/images/phoneScreenshots',
		'/<locale>/images/sevenInchScreenshots',
		'/<locale>/images/tenInchScreenshots',
		'/<locale>/images/tvScreenshots',
		'/<locale>/images/wearScreenshots',
	];
}

// Path: guides.iosMetadata
class TranslationsGuidesIosMetadataTr {
	TranslationsGuidesIosMetadataTr.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// tr: 'iOS Metadata & Screenshots'
	String get title => 'iOS Metadata & Screenshots';

	/// tr: 'App Store metadata/screenshot yapısını düzeltip sonra aksiyonu tekrar çalıştırın.'
	String get summary => 'App Store metadata/screenshot yapısını düzeltip sonra aksiyonu tekrar çalıştırın.';

	List<String> get checklist => [
		'Her locale için metadata klasörü oluşturun (ör. tr-TR, en-US).',
		'Locale klasörlerinde .txt metadata ve whats_new.txt dosyalarını ekleyin.',
		'review_information klasörüne iletişim dosyalarını koyun.',
		'screenshots/<locale> altında en az bir screenshot ekleyin.',
	];

	/// tr: '/appleTV (opsiyonel)'
	String get appleTvSuffix => '/appleTV (opsiyonel)';

	/// tr: '/iMessage (opsiyonel)'
	String get iMessageSuffix => '/iMessage (opsiyonel)';
}

/// The flat map containing all translations for locale <tr>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'homeTitle' => 'Ana Sayfa',
			'androidTitle' => 'Android',
			'iosTitle' => 'iOS',
			'generalTitle' => 'Genel',
			'guidesTitle' => 'Kılavuz',
			'runTitle' => 'Çalıştır',
			'shortcuts' => 'Hızlı Erişim',
			'categories' => 'Kategoriler',
			'noAction' => 'Aksiyon bulunamadı.',
			'pressEnterToRun' => 'Enter: Çalıştır',
			'upDownNavigate' => '↑/↓: Seçim değiştir',
			'footerHints' => 'A:Android I:iOS G:Genel H:Ana D:Guide L:Dil Q:Çıkış',
			'lastRun' => 'Son Çalıştırma',
			'command' => 'Komut',
			'logs' => 'Loglar',
			'progress' => 'İlerleme',
			'currentFile' => 'Aktif Dosya',
			'waitingLogs' => 'Log akışı bekleniyor...',
			'commandPalettePlaceholder' => '/ sayfa veya aksiyon ara',
			'commandPaletteTitle' => 'Komut Paleti',
			'commandPaletteNoResult' => 'Eşleşme bulunamadı',
			'shellBrand' => '⚡ Fast CLI',
			'pages' => 'Sayfalar',
			'validationFailed' => 'Doğrulama başarısız',
			'blockedByGuide' => 'Aksiyon kılavuz eksikleri nedeniyle durduruldu.',
			'runConfirmTitle' => 'Çalıştırma Onayı',
			'runConfirmMessage' => ({required Object actionTitle}) => '"${actionTitle}" aksiyonunu çalıştırmak istiyor musun?',
			'runConfirmHint' => 'Y/Enter: Onayla · N/Esc: İptal',
			'runConfirmApprove' => 'Onayla (Y/Enter)',
			'runConfirmCancel' => 'İptal (N/Esc)',
			'quitConfirmTitle' => 'Çıkış Onayı',
			'quitConfirmMessage' => 'Uygulamadan çıkmak istediğine emin misin?',
			'retry' => 'R: Tekrar dene',
			'back' => 'B: Geri',
			'copyOutput' => 'C/Ctrl+Shift+C: Çıktıyı kopyala',
			'copiedOutput' => 'Çıktı panoya kopyalandı.',
			'confirmPrompt' => 'Bu aksiyon onay gerektirir. Y ile onayla.',
			'guideRetry' => 'R: Bu aksiyonu tekrar çalıştır',
			'guideFallback' => 'Bu konu için kılavuz yok.',
			'dryRunLabel' => 'Dry-run (simülasyon)',
			'localeLabel' => 'Dil',
			'prompt.twoFactorTitle' => 'İki faktörlü doğrulama kodu',
			'prompt.twoFactorBody' => ({required Object digits}) => '${digits} haneli kodu giriniz',
			'prompt.twoFactorHint' => ({required Object digits}) => '${digits} haneli kod',
			'prompt.yesNoTitle' => 'Onay',
			'prompt.yesNoBody' => 'Lane evet/hayır yanıtı bekliyor.',
			'prompt.trustComputerTitle' => 'Bu bilgisayara güveniliyor mu?',
			'prompt.trustComputerBody' => 'Apple, bu bilgisayara App Store Connect için güvenip güvenmediğini soruyor.',
			'prompt.chooseIndexTitle' => 'Bir seçenek seçin',
			'prompt.chooseIndexBody' => ({required Object lo, required Object hi}) => '${lo} ile ${hi} arasında bir sayı seçin',
			'prompt.freeFormTitle' => 'Lane giriş bekliyor',
			'prompt.submit' => 'Gönder',
			'prompt.cancel' => 'İptal',
			'prompt.yes' => 'Evet',
			'prompt.no' => 'Hayır',
			'prompt.errorWrongLength' => ({required Object n}) => '${n} haneli olmalı',
			'prompt.errorOnlyDigits' => 'Yalnızca rakam',
			'prompt.errorYesOrNo' => 'y/n giriniz',
			'prompt.errorOutOfRange' => ({required Object lo, required Object hi}) => '${lo}-${hi} arası olmalı',
			'prompt.errorRequired' => 'Zorunlu',
			'status.idle' => 'Bekleniyor',
			'status.validating' => 'Doğrulanıyor',
			'status.blocked' => 'Bloklandı',
			'status.confirmationRequired' => 'Onay Bekliyor',
			'status.running' => 'Çalışıyor',
			'status.succeeded' => 'Başarılı',
			'status.failed' => 'Başarısız',
			'status.dryRun' => 'Dry-run tamamlandı',
			'palette.homeTitle' => 'Ana Sayfa',
			'palette.generalTitle' => 'Genel',
			'palette.guideAndroidMetadata' => 'Guide: Android Metadata',
			'palette.guideIosMetadata' => 'Guide: iOS Metadata',
			'palette.quitTitle' => 'Çıkış',
			'palette.quitSubtitle' => 'q, quit, exit',
			'guides.androidMetadata.title' => 'Android Metadata & Screenshots',
			'guides.androidMetadata.summary' => 'Play Store metadata ve screenshot klasörlerini bu yapıda hazırlayın.',
			'guides.androidMetadata.checklist.0' => 'Locale klasörü açın (ör. tr-TR, en-US).',
			'guides.androidMetadata.checklist.1' => 'title.txt, short_description.txt, full_description.txt ekleyin.',
			'guides.androidMetadata.checklist.2' => 'changelogs/<version_code>.txt ile release notes dosyası ekleyin.',
			'guides.androidMetadata.checklist.3' => 'images altında tüm screenshot klasörlerini oluşturun.',
			'guides.androidMetadata.checklist.4' => 'En az bir ekran görüntüsünü .png/.jpg olarak ekleyin.',
			'guides.androidMetadata.pathSuffixes.0' => '/<locale>/title.txt',
			'guides.androidMetadata.pathSuffixes.1' => '/<locale>/short_description.txt',
			'guides.androidMetadata.pathSuffixes.2' => '/<locale>/full_description.txt',
			'guides.androidMetadata.pathSuffixes.3' => '/<locale>/changelogs/<version_code>.txt',
			'guides.androidMetadata.pathSuffixes.4' => '/<locale>/images/phoneScreenshots',
			'guides.androidMetadata.pathSuffixes.5' => '/<locale>/images/sevenInchScreenshots',
			'guides.androidMetadata.pathSuffixes.6' => '/<locale>/images/tenInchScreenshots',
			'guides.androidMetadata.pathSuffixes.7' => '/<locale>/images/tvScreenshots',
			'guides.androidMetadata.pathSuffixes.8' => '/<locale>/images/wearScreenshots',
			'guides.iosMetadata.title' => 'iOS Metadata & Screenshots',
			'guides.iosMetadata.summary' => 'App Store metadata/screenshot yapısını düzeltip sonra aksiyonu tekrar çalıştırın.',
			'guides.iosMetadata.checklist.0' => 'Her locale için metadata klasörü oluşturun (ör. tr-TR, en-US).',
			'guides.iosMetadata.checklist.1' => 'Locale klasörlerinde .txt metadata ve whats_new.txt dosyalarını ekleyin.',
			'guides.iosMetadata.checklist.2' => 'review_information klasörüne iletişim dosyalarını koyun.',
			'guides.iosMetadata.checklist.3' => 'screenshots/<locale> altında en az bir screenshot ekleyin.',
			'guides.iosMetadata.appleTvSuffix' => '/appleTV (opsiyonel)',
			'guides.iosMetadata.iMessageSuffix' => '/iMessage (opsiyonel)',
			_ => null,
		};
	}
}
