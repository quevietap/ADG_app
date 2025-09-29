import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_settings_service.dart';
import '../services/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'English';
  String _selectedTheme = 'Dark';

  final List<String> _languages = ['English', 'Filipino', 'Spanish'];
  final List<String> _themes = ['Light', 'Dark']; // Removed Auto option
  late AppSettingsService _settingsService;

  @override
  void initState() {
    super.initState();
    _settingsService = AppSettingsService();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      // Load app-wide settings from service
      _notificationsEnabled = _settingsService.notificationsEnabled;
      _selectedLanguage = _settingsService.selectedLanguage;
      _selectedTheme =
          _settingsService.themeMode == ThemeMode.light ? 'Light' : 'Dark';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settingsService,
      builder: (context, child) {
        // Update local state when settings change
        _selectedLanguage = _settingsService.selectedLanguage;
        _selectedTheme =
            _settingsService.themeMode == ThemeMode.light ? 'Light' : 'Dark';
        _notificationsEnabled = _settingsService.notificationsEnabled;

        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.translate('settings',
                AppLocalizations.getLanguageCode(_selectedLanguage))),
            automaticallyImplyLeading: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Notification Settings (Device Level)
              _buildSectionHeader(AppLocalizations.translate(
                  'notification_settings',
                  AppLocalizations.getLanguageCode(_selectedLanguage))),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(AppLocalizations.translate(
                          'enable_notifications',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      subtitle: Text(AppLocalizations.translate(
                          'notifications_desc',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      value: _notificationsEnabled,
                      onChanged: (value) async {
                        setState(() {
                          _notificationsEnabled = value;
                        });

                        // Update app-wide notification setting
                        await _settingsService.setNotificationsEnabled(value);
                        HapticFeedback.lightImpact();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.translate(
                                value
                                    ? 'notifications_enabled_msg'
                                    : 'notifications_disabled_msg',
                                AppLocalizations.getLanguageCode(
                                    _selectedLanguage))),
                            backgroundColor:
                                value ? Colors.green : Colors.orange,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      secondary:
                          const Icon(Icons.notifications, color: Colors.blue),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Appearance Settings (Device Level)
              _buildSectionHeader(AppLocalizations.translate('appearance',
                  AppLocalizations.getLanguageCode(_selectedLanguage))),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        _selectedTheme == 'Light'
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        color: Colors.indigo,
                      ),
                      title: Text(AppLocalizations.translate('theme',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      subtitle: Text(AppLocalizations.translate(
                          _selectedTheme == 'Light'
                              ? 'light_mode'
                              : 'dark_mode',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      onTap: () => _showThemeDialog(),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                    ListTile(
                      leading: Text(
                        _selectedLanguage == 'English'
                            ? '🇺🇸'
                            : _selectedLanguage == 'Filipino'
                                ? '🇵🇭'
                                : '🇪🇸',
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(AppLocalizations.translate('language',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      subtitle: Text(_selectedLanguage),
                      onTap: () => _showLanguageDialog(),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // About Section
              _buildSectionHeader(AppLocalizations.translate('about',
                  AppLocalizations.getLanguageCode(_selectedLanguage))),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading:
                          const Icon(Icons.info_outline, color: Colors.blue),
                      title: Text(AppLocalizations.translate('about_tinysync',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      subtitle: Text(AppLocalizations.translate('version',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      onTap: () => _showAboutDialog(),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined,
                          color: Colors.green),
                      title: Text(AppLocalizations.translate('privacy_policy',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      onTap: () {
                        // TODO: Implement privacy policy view
                      },
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined,
                          color: Colors.orange),
                      title: Text(AppLocalizations.translate('terms_of_service',
                          AppLocalizations.getLanguageCode(_selectedLanguage))),
                      onTap: () {
                        // TODO: Implement terms of service view
                      },
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Future<void> _showLanguageDialog() async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.translate('select_language',
              AppLocalizations.getLanguageCode(_selectedLanguage))),
          content: SingleChildScrollView(
            child: ListBody(
              children: _languages.map((String language) {
                return ListTile(
                  title: Text(language),
                  leading: Text(
                    language == 'English'
                        ? '🇺🇸'
                        : language == 'Filipino'
                            ? '🇵🇭'
                            : '🇪🇸',
                    style: const TextStyle(fontSize: 24),
                  ),
                  selected: language == _selectedLanguage,
                  onTap: () async {
                    setState(() {
                      _selectedLanguage = language;
                    });

                    // Update app-wide language setting
                    await _settingsService.setLanguage(language);

                    Navigator.pop(context);
                    HapticFeedback.selectionClick();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${AppLocalizations.translate('language_changed_to', AppLocalizations.getLanguageCode(language))} $language'),
                        backgroundColor: Colors.teal,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showThemeDialog() async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.translate('select_theme',
              AppLocalizations.getLanguageCode(_selectedLanguage))),
          content: SingleChildScrollView(
            child: ListBody(
              children: _themes.map((String theme) {
                return ListTile(
                  title: Text(AppLocalizations.translate(
                      theme == 'Light' ? 'light_mode' : 'dark_mode',
                      AppLocalizations.getLanguageCode(_selectedLanguage))),
                  leading: Icon(
                    theme == 'Dark' ? Icons.dark_mode : Icons.light_mode,
                  ),
                  selected: theme == _selectedTheme,
                  onTap: () async {
                    setState(() {
                      _selectedTheme = theme;
                    });

                    // Update app-wide theme setting with smooth transition
                    final newMode =
                        theme == 'Light' ? ThemeMode.light : ThemeMode.dark;
                    await _settingsService.setThemeMode(newMode);

                    Navigator.pop(context);
                    HapticFeedback.selectionClick();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${AppLocalizations.translate('theme_changed_to', AppLocalizations.getLanguageCode(_selectedLanguage))} $theme'),
                        backgroundColor: Colors.indigo,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.translate('about_tinysync',
              AppLocalizations.getLanguageCode(_selectedLanguage))),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TINYSYNC is a real-time alert and micro-sleep monitoring system made for drivers of ADG Company.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                Text('Version: 1.0.0'),
                Text('© 2024 ADG Technologies'),
                SizedBox(height: 16),
                Text(
                  'Developed by: Mark Beriso, Jc Magdaraog, Kate Millares, Carl Johnrey',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.translate('close',
                  AppLocalizations.getLanguageCode(_selectedLanguage))),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

}
