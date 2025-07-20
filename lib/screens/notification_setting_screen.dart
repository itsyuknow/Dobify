import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';
import '/widgets/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final NotificationService notificationService = NotificationService();

  Map<String, bool> preferences = {};
  Map<String, Map<String, bool>> detailedSettings = {};
  bool isLoading = true;
  bool hasSystemPermission = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadSettings();
    _checkSystemPermission();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0.0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() => isLoading = true);

      // Get basic preferences
      final prefResponse = await supabase
          .from('user_preferences')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (prefResponse != null) {
        preferences = {
          'notifications_enabled': prefResponse['notifications_enabled'] ?? true,
          'push_notifications': prefResponse['push_notifications'] ?? true,
          'email_notifications': prefResponse['email_notifications'] ?? true,
          'sms_notifications': prefResponse['sms_notifications'] ?? false,
          'order_updates': prefResponse['order_updates'] ?? true,
          'promotion_notifications': prefResponse['promotion_notifications'] ?? true,
          'system_notifications': prefResponse['system_notifications'] ?? true,
        };
      } else {
        preferences = {
          'notifications_enabled': true,
          'push_notifications': true,
          'email_notifications': true,
          'sms_notifications': false,
          'order_updates': true,
          'promotion_notifications': true,
          'system_notifications': true,
        };
      }

      // Get detailed settings
      final detailResponse = await supabase
          .from('notification_settings')
          .select()
          .eq('user_id', user.id);

      detailedSettings = {};
      for (final setting in detailResponse) {
        final type = setting['notification_type'] as String;
        detailedSettings[type] = {
          'push_enabled': setting['push_enabled'] ?? true,
          'email_enabled': setting['email_enabled'] ?? true,
          'sms_enabled': setting['sms_enabled'] ?? false,
          'in_app_enabled': setting['in_app_enabled'] ?? true,
        };
      }

      // Initialize default settings if missing
      for (final type in ['order', 'promotion', 'system', 'general']) {
        if (!detailedSettings.containsKey(type)) {
          detailedSettings[type] = {
            'push_enabled': true,
            'email_enabled': true,
            'sms_enabled': false,
            'in_app_enabled': true,
          };
        }
      }

      setState(() => isLoading = false);
    } catch (e) {
      print('Error loading settings: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _checkSystemPermission() async {
    hasSystemPermission = await notificationService.areNotificationsEnabled();
    setState(() {});
  }

  Future<void> _updatePreference(String key, bool value) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() {
        preferences[key] = value;
      });

      await supabase.from('user_preferences').upsert({
        'user_id': user.id,
        key: value,
        'updated_at': DateTime.now().toIso8601String(),
      });

      HapticFeedback.lightImpact();
      _showSuccessSnackBar('Settings updated');
    } catch (e) {
      print('Error updating preference: $e');
      _showErrorSnackBar('Failed to update settings');
      // Revert the change
      setState(() {
        preferences[key] = !value;
      });
    }
  }

  Future<void> _updateDetailedSetting(String type, String settingKey, bool value) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() {
        detailedSettings[type]![settingKey] = value;
      });

      await supabase.from('notification_settings').upsert({
        'user_id': user.id,
        'notification_type': type,
        settingKey: value,
        'updated_at': DateTime.now().toIso8601String(),
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      print('Error updating detailed setting: $e');
      _showErrorSnackBar('Failed to update setting');
      // Revert the change
      setState(() {
        detailedSettings[type]![settingKey] = !value;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.error_outline, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: isLoading
              ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading settings...', style: TextStyle(fontSize: 16)),
              ],
            ),
          )
              : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSystemPermissionCard(),
                const SizedBox(height: 20),
                _buildGeneralSettingsCard(),
                const SizedBox(height: 20),
                _buildDetailedSettingsCard(),
                const SizedBox(height: 20),
                _buildQuickActionsCard(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Notification Settings',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
        ),
      ),
    );
  }

  Widget _buildSystemPermissionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasSystemPermission
              ? [Colors.green.withOpacity(0.1), Colors.green.withOpacity(0.05)]
              : [Colors.orange.withOpacity(0.1), Colors.orange.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasSystemPermission
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasSystemPermission
                    ? [Colors.green, Colors.green.shade700]
                    : [Colors.orange, Colors.orange.shade700],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasSystemPermission ? Icons.check_circle : Icons.warning_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSystemPermission ? 'Notifications Enabled' : 'Permission Required',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: hasSystemPermission ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasSystemPermission
                      ? 'You\'ll receive notifications from ironXpress'
                      : 'Enable notifications to get order updates',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (!hasSystemPermission)
            ElevatedButton(
              onPressed: () async {
                await notificationService.openNotificationSettings();
                await Future.delayed(const Duration(seconds: 1));
                _checkSystemPermission();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text(
                'Enable',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeneralSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryColor.withOpacity(0.2), kPrimaryColor.withOpacity(0.1)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.tune_rounded, color: kPrimaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'General Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          _buildSettingTile(
            icon: Icons.notifications_active_rounded,
            title: 'All Notifications',
            subtitle: 'Receive all types of notifications',
            value: preferences['notifications_enabled'] ?? true,
            onChanged: (value) => _updatePreference('notifications_enabled', value),
            gradient: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          ),
          _buildDivider(),
          _buildSettingTile(
            icon: Icons.phone_android_rounded,
            title: 'Push Notifications',
            subtitle: 'Get notifications on your device',
            value: preferences['push_notifications'] ?? true,
            onChanged: (value) => _updatePreference('push_notifications', value),
            gradient: [Colors.blue, Colors.blue.shade700],
          ),
          _buildDivider(),
          _buildSettingTile(
            icon: Icons.email_rounded,
            title: 'Email Notifications',
            subtitle: 'Receive notifications via email',
            value: preferences['email_notifications'] ?? true,
            onChanged: (value) => _updatePreference('email_notifications', value),
            gradient: [Colors.green, Colors.green.shade700],
          ),
          _buildDivider(),
          _buildSettingTile(
            icon: Icons.sms_rounded,
            title: 'SMS Notifications',
            subtitle: 'Get important updates via SMS',
            value: preferences['sms_notifications'] ?? false,
            onChanged: (value) => _updatePreference('sms_notifications', value),
            gradient: [Colors.orange, Colors.orange.shade700],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.withOpacity(0.2), Colors.purple.withOpacity(0.1)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.category_rounded, color: Colors.purple, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Notification Types',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          _buildNotificationTypeSection('order', 'Order Updates', 'Pickup, delivery, and status updates', Icons.shopping_bag_rounded, [kPrimaryColor, kPrimaryColor.withOpacity(0.8)]),
          _buildDivider(),
          _buildNotificationTypeSection('promotion', 'Promotions & Offers', 'Special deals and discount codes', Icons.local_offer_rounded, [Colors.orange, Colors.orange.shade700]),
          _buildDivider(),
          _buildNotificationTypeSection('system', 'System Notifications', 'App updates and important announcements', Icons.settings_rounded, [Colors.blue, Colors.blue.shade700]),
          _buildDivider(),
          _buildNotificationTypeSection('general', 'General Notifications', 'Tips, news, and other updates', Icons.info_rounded, [Colors.grey.shade600, Colors.grey.shade700]),
        ],
      ),
    );
  }

  Widget _buildNotificationTypeSection(String type, String title, String subtitle, IconData icon, List<Color> gradient) {
    final settings = detailedSettings[type] ?? {};
    final isAnyEnabled = settings.values.any((enabled) => enabled == true);

    return ExpansionTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isAnyEnabled ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isAnyEnabled ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isAnyEnabled ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
          child: Column(
            children: [
              _buildSubSettingTile(
                'Push',
                'Get push notifications',
                Icons.notifications_rounded,
                settings['push_enabled'] ?? true,
                    (value) => _updateDetailedSetting(type, 'push_enabled', value),
              ),
              const SizedBox(height: 8),
              _buildSubSettingTile(
                'Email',
                'Receive via email',
                Icons.email_rounded,
                settings['email_enabled'] ?? true,
                    (value) => _updateDetailedSetting(type, 'email_enabled', value),
              ),
              const SizedBox(height: 8),
              _buildSubSettingTile(
                'SMS',
                'Get text messages',
                Icons.sms_rounded,
                settings['sms_enabled'] ?? false,
                    (value) => _updateDetailedSetting(type, 'sms_enabled', value),
              ),
              const SizedBox(height: 8),
              _buildSubSettingTile(
                'In-App',
                'Show in notification center',
                Icons.app_registration_rounded,
                settings['in_app_enabled'] ?? true,
                    (value) => _updateDetailedSetting(type, 'in_app_enabled', value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubSettingTile(String title, String subtitle, IconData icon, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: value ? kPrimaryColor.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: value ? kPrimaryColor : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: kPrimaryColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.withOpacity(0.2), Colors.indigo.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.flash_on_rounded, color: Colors.indigo, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.notifications_off_rounded,
                  title: 'Turn Off All',
                  subtitle: 'Disable all notifications',
                  gradient: [Colors.red, Colors.red.shade700],
                  onTap: () => _turnOffAllNotifications(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.notifications_active_rounded,
                  title: 'Turn On All',
                  subtitle: 'Enable all notifications',
                  gradient: [Colors.green, Colors.green.shade700],
                  onTap: () => _turnOnAllNotifications(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _buildQuickActionButton(
              icon: Icons.refresh_rounded,
              title: 'Reset to Defaults',
              subtitle: 'Restore recommended notification settings',
              gradient: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
              onTap: () => _resetToDefaults(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required List<Color> gradient,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: kPrimaryColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: Colors.grey.shade200,
    );
  }

  Future<void> _turnOffAllNotifications() async {
    final confirmed = await _showConfirmationDialog(
      'Turn Off All Notifications',
      'Are you sure you want to disable all notifications? You won\'t receive any updates about your orders or promotions.',
      'Turn Off',
      Colors.red,
    );

    if (confirmed) {
      // Update preferences
      for (final key in preferences.keys) {
        await _updatePreference(key, false);
      }

      // Update detailed settings
      for (final type in detailedSettings.keys) {
        for (final setting in detailedSettings[type]!.keys) {
          await _updateDetailedSetting(type, setting, false);
        }
      }

      _showSuccessSnackBar('All notifications turned off');
    }
  }

  Future<void> _turnOnAllNotifications() async {
    final confirmed = await _showConfirmationDialog(
      'Turn On All Notifications',
      'This will enable all notification types and delivery methods. You can customize individual settings later.',
      'Turn On',
      Colors.green,
    );

    if (confirmed) {
      // Update preferences
      for (final key in preferences.keys) {
        await _updatePreference(key, true);
      }

      // Update detailed settings
      for (final type in detailedSettings.keys) {
        for (final setting in detailedSettings[type]!.keys) {
          await _updateDetailedSetting(type, setting, true);
        }
      }

      _showSuccessSnackBar('All notifications turned on');
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await _showConfirmationDialog(
      'Reset to Defaults',
      'This will restore the recommended notification settings. Your current preferences will be lost.',
      'Reset',
      kPrimaryColor,
    );

    if (confirmed) {
      // Reset to default preferences
      final defaults = {
        'notifications_enabled': true,
        'push_notifications': true,
        'email_notifications': true,
        'sms_notifications': false,
        'order_updates': true,
        'promotion_notifications': true,
        'system_notifications': true,
      };

      for (final entry in defaults.entries) {
        await _updatePreference(entry.key, entry.value);
      }

      // Reset detailed settings to defaults
      final defaultDetailedSettings = {
        'push_enabled': true,
        'email_enabled': true,
        'sms_enabled': false,
        'in_app_enabled': true,
      };

      for (final type in detailedSettings.keys) {
        for (final entry in defaultDetailedSettings.entries) {
          await _updateDetailedSetting(type, entry.key, entry.value);
        }
      }

      _showSuccessSnackBar('Settings reset to defaults');
    }
  }

  Future<bool> _showConfirmationDialog(String title, String content, String actionText, Color actionColor) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: actionColor),
            child: Text(actionText, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }
}