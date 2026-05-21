///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsEn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsEn _root = this; // ignore: unused_field

	@override 
	TranslationsEn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEn(meta: meta ?? this.$meta);

	// Translations
	@override String get homeTitle => 'Home';
	@override String get androidTitle => 'Android';
	@override String get iosTitle => 'iOS';
	@override String get generalTitle => 'General';
	@override String get guidesTitle => 'Guides';
	@override String get runTitle => 'Run';
	@override String get shortcuts => 'Shortcuts';
	@override String get categories => 'Categories';
	@override String get noAction => 'No actions found.';
	@override String get pressEnterToRun => 'Enter: Execute';
	@override String get upDownNavigate => '↑/↓: Change selection';
	@override String get footerHints => 'A:Android I:iOS G:General H:Home D:Guide L:Lang Q:Quit';
	@override String get lastRun => 'Last Run';
	@override String get command => 'Command';
	@override String get logs => 'Logs';
	@override String get progress => 'Progress';
	@override String get currentFile => 'Current File';
	@override String get waitingLogs => 'Waiting for log stream...';
	@override String get commandPalettePlaceholder => '/ search pages or actions';
	@override String get commandPaletteTitle => 'Command Palette';
	@override String get commandPaletteNoResult => 'No matches';
	@override String get shellBrand => '⚡ Fast CLI';
	@override String get pages => 'Pages';
	@override String get validationFailed => 'Validation failed';
	@override String get blockedByGuide => 'Action blocked due to guide/preflight issues.';
	@override String get runConfirmTitle => 'Run Confirmation';
	@override String runConfirmMessage({required Object actionTitle}) => 'Do you want to run "${actionTitle}"?';
	@override String get runConfirmHint => 'Y/Enter: Confirm · N/Esc: Cancel';
	@override String get runConfirmApprove => 'Confirm (Y/Enter)';
	@override String get runConfirmCancel => 'Cancel (N/Esc)';
	@override String get quitConfirmTitle => 'Quit Confirmation';
	@override String get quitConfirmMessage => 'Are you sure you want to quit?';
	@override String get retry => 'R: Retry';
	@override String get back => 'B: Back';
	@override String get copyOutput => 'C/Ctrl+Shift+C: Copy output';
	@override String get copiedOutput => 'Output copied to clipboard.';
	@override String get confirmPrompt => 'This action requires confirmation. Press Y to continue.';
	@override String get guideRetry => 'R: Retry this action';
	@override String get guideFallback => 'No guide for this topic.';
	@override String get dryRunLabel => 'Dry-run';
	@override String get localeLabel => 'Language';
	@override late final _TranslationsPromptEn prompt = _TranslationsPromptEn._(_root);
	@override late final _TranslationsStatusEn status = _TranslationsStatusEn._(_root);
	@override late final _TranslationsPaletteEn palette = _TranslationsPaletteEn._(_root);
	@override late final _TranslationsGuidesEn guides = _TranslationsGuidesEn._(_root);
}

// Path: prompt
class _TranslationsPromptEn extends TranslationsPromptTr {
	_TranslationsPromptEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get twoFactorTitle => 'Two-factor authentication code';
	@override String twoFactorBody({required Object digits}) => 'Enter the ${digits}-digit code';
	@override String twoFactorHint({required Object digits}) => '${digits}-digit code';
	@override String get yesNoTitle => 'Confirmation';
	@override String get yesNoBody => 'The lane is waiting for a yes/no answer.';
	@override String get trustComputerTitle => 'Trust this computer?';
	@override String get trustComputerBody => 'Apple is asking whether to trust this computer for App Store Connect.';
	@override String get chooseIndexTitle => 'Pick an option';
	@override String chooseIndexBody({required Object lo, required Object hi}) => 'Pick a number between ${lo} and ${hi}';
	@override String get freeFormTitle => 'The lane is waiting for input';
	@override String get submit => 'Submit';
	@override String get cancel => 'Cancel';
	@override String get yes => 'Yes';
	@override String get no => 'No';
	@override String errorWrongLength({required Object n}) => 'Must be ${n} digits';
	@override String get errorOnlyDigits => 'Digits only';
	@override String get errorYesOrNo => 'Type y or n';
	@override String errorOutOfRange({required Object lo, required Object hi}) => 'Must be ${lo}-${hi}';
	@override String get errorRequired => 'Required';
}

// Path: status
class _TranslationsStatusEn extends TranslationsStatusTr {
	_TranslationsStatusEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get idle => 'Idle';
	@override String get validating => 'Validating';
	@override String get blocked => 'Blocked';
	@override String get confirmationRequired => 'Needs Confirmation';
	@override String get running => 'Running';
	@override String get succeeded => 'Succeeded';
	@override String get failed => 'Failed';
	@override String get dryRun => 'Dry-run completed';
}

// Path: palette
class _TranslationsPaletteEn extends TranslationsPaletteTr {
	_TranslationsPaletteEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get homeTitle => 'Home';
	@override String get generalTitle => 'General';
	@override String get guideAndroidMetadata => 'Guide: Android Metadata';
	@override String get guideIosMetadata => 'Guide: iOS Metadata';
	@override String get quitTitle => 'Quit';
	@override String get quitSubtitle => 'q, quit, exit';
}

// Path: guides
class _TranslationsGuidesEn extends TranslationsGuidesTr {
	_TranslationsGuidesEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsGuidesAndroidMetadataEn androidMetadata = _TranslationsGuidesAndroidMetadataEn._(_root);
	@override late final _TranslationsGuidesIosMetadataEn iosMetadata = _TranslationsGuidesIosMetadataEn._(_root);
}

// Path: guides.androidMetadata
class _TranslationsGuidesAndroidMetadataEn extends TranslationsGuidesAndroidMetadataTr {
	_TranslationsGuidesAndroidMetadataEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Android Metadata & Screenshots';
	@override String get summary => 'Prepare Play Store metadata and screenshot folders in this structure.';
	@override List<String> get checklist => [
		'Create a locale directory (e.g. tr-TR, en-US).',
		'Add title.txt, short_description.txt, full_description.txt.',
		'Add release notes file as changelogs/<version_code>.txt.',
		'Create every screenshot folder under images.',
		'Add at least one .png/.jpg screenshot.',
	];
	@override List<String> get pathSuffixes => [
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
class _TranslationsGuidesIosMetadataEn extends TranslationsGuidesIosMetadataTr {
	_TranslationsGuidesIosMetadataEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'iOS Metadata & Screenshots';
	@override String get summary => 'Fix App Store metadata/screenshot structure, then retry the action.';
	@override List<String> get checklist => [
		'Create locale metadata folders (e.g. tr-TR, en-US).',
		'Add .txt metadata files and whats_new.txt under each locale folder.',
		'Place contact files under review_information.',
		'Add at least one screenshot under screenshots/<locale>.',
	];
	@override String get appleTvSuffix => '/appleTV (optional)';
	@override String get iMessageSuffix => '/iMessage (optional)';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEn {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'homeTitle' => 'Home',
			'androidTitle' => 'Android',
			'iosTitle' => 'iOS',
			'generalTitle' => 'General',
			'guidesTitle' => 'Guides',
			'runTitle' => 'Run',
			'shortcuts' => 'Shortcuts',
			'categories' => 'Categories',
			'noAction' => 'No actions found.',
			'pressEnterToRun' => 'Enter: Execute',
			'upDownNavigate' => '↑/↓: Change selection',
			'footerHints' => 'A:Android I:iOS G:General H:Home D:Guide L:Lang Q:Quit',
			'lastRun' => 'Last Run',
			'command' => 'Command',
			'logs' => 'Logs',
			'progress' => 'Progress',
			'currentFile' => 'Current File',
			'waitingLogs' => 'Waiting for log stream...',
			'commandPalettePlaceholder' => '/ search pages or actions',
			'commandPaletteTitle' => 'Command Palette',
			'commandPaletteNoResult' => 'No matches',
			'shellBrand' => '⚡ Fast CLI',
			'pages' => 'Pages',
			'validationFailed' => 'Validation failed',
			'blockedByGuide' => 'Action blocked due to guide/preflight issues.',
			'runConfirmTitle' => 'Run Confirmation',
			'runConfirmMessage' => ({required Object actionTitle}) => 'Do you want to run "${actionTitle}"?',
			'runConfirmHint' => 'Y/Enter: Confirm · N/Esc: Cancel',
			'runConfirmApprove' => 'Confirm (Y/Enter)',
			'runConfirmCancel' => 'Cancel (N/Esc)',
			'quitConfirmTitle' => 'Quit Confirmation',
			'quitConfirmMessage' => 'Are you sure you want to quit?',
			'retry' => 'R: Retry',
			'back' => 'B: Back',
			'copyOutput' => 'C/Ctrl+Shift+C: Copy output',
			'copiedOutput' => 'Output copied to clipboard.',
			'confirmPrompt' => 'This action requires confirmation. Press Y to continue.',
			'guideRetry' => 'R: Retry this action',
			'guideFallback' => 'No guide for this topic.',
			'dryRunLabel' => 'Dry-run',
			'localeLabel' => 'Language',
			'prompt.twoFactorTitle' => 'Two-factor authentication code',
			'prompt.twoFactorBody' => ({required Object digits}) => 'Enter the ${digits}-digit code',
			'prompt.twoFactorHint' => ({required Object digits}) => '${digits}-digit code',
			'prompt.yesNoTitle' => 'Confirmation',
			'prompt.yesNoBody' => 'The lane is waiting for a yes/no answer.',
			'prompt.trustComputerTitle' => 'Trust this computer?',
			'prompt.trustComputerBody' => 'Apple is asking whether to trust this computer for App Store Connect.',
			'prompt.chooseIndexTitle' => 'Pick an option',
			'prompt.chooseIndexBody' => ({required Object lo, required Object hi}) => 'Pick a number between ${lo} and ${hi}',
			'prompt.freeFormTitle' => 'The lane is waiting for input',
			'prompt.submit' => 'Submit',
			'prompt.cancel' => 'Cancel',
			'prompt.yes' => 'Yes',
			'prompt.no' => 'No',
			'prompt.errorWrongLength' => ({required Object n}) => 'Must be ${n} digits',
			'prompt.errorOnlyDigits' => 'Digits only',
			'prompt.errorYesOrNo' => 'Type y or n',
			'prompt.errorOutOfRange' => ({required Object lo, required Object hi}) => 'Must be ${lo}-${hi}',
			'prompt.errorRequired' => 'Required',
			'status.idle' => 'Idle',
			'status.validating' => 'Validating',
			'status.blocked' => 'Blocked',
			'status.confirmationRequired' => 'Needs Confirmation',
			'status.running' => 'Running',
			'status.succeeded' => 'Succeeded',
			'status.failed' => 'Failed',
			'status.dryRun' => 'Dry-run completed',
			'palette.homeTitle' => 'Home',
			'palette.generalTitle' => 'General',
			'palette.guideAndroidMetadata' => 'Guide: Android Metadata',
			'palette.guideIosMetadata' => 'Guide: iOS Metadata',
			'palette.quitTitle' => 'Quit',
			'palette.quitSubtitle' => 'q, quit, exit',
			'guides.androidMetadata.title' => 'Android Metadata & Screenshots',
			'guides.androidMetadata.summary' => 'Prepare Play Store metadata and screenshot folders in this structure.',
			'guides.androidMetadata.checklist.0' => 'Create a locale directory (e.g. tr-TR, en-US).',
			'guides.androidMetadata.checklist.1' => 'Add title.txt, short_description.txt, full_description.txt.',
			'guides.androidMetadata.checklist.2' => 'Add release notes file as changelogs/<version_code>.txt.',
			'guides.androidMetadata.checklist.3' => 'Create every screenshot folder under images.',
			'guides.androidMetadata.checklist.4' => 'Add at least one .png/.jpg screenshot.',
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
			'guides.iosMetadata.summary' => 'Fix App Store metadata/screenshot structure, then retry the action.',
			'guides.iosMetadata.checklist.0' => 'Create locale metadata folders (e.g. tr-TR, en-US).',
			'guides.iosMetadata.checklist.1' => 'Add .txt metadata files and whats_new.txt under each locale folder.',
			'guides.iosMetadata.checklist.2' => 'Place contact files under review_information.',
			'guides.iosMetadata.checklist.3' => 'Add at least one screenshot under screenshots/<locale>.',
			'guides.iosMetadata.appleTvSuffix' => '/appleTV (optional)',
			'guides.iosMetadata.iMessageSuffix' => '/iMessage (optional)',
			_ => null,
		};
	}
}
