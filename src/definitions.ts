export interface AlarmPlugin {
  /**
   * Set an alarm with the specified settings
   */
  setAlarm(options: { alarmSettings: AlarmSettings }): Promise<void>;

  /**
   * Stop a specific alarm by ID
   */
  stopAlarm(options: { alarmId: number }): Promise<void>;

  /**
   * Stop all active alarms
   */
  stopAll(): Promise<void>;

  /**
   * Check if an alarm is currently ringing
   */
  isRinging(options: { alarmId?: number }): Promise<{ isRinging: boolean }>;

  /**
   * Get all scheduled alarms
   */
  getAlarms(): Promise<{ alarms: AlarmSettings[] }>;

  /**
   * Set warning notification when app is killed
   */
  setWarningNotificationOnKill(options: { title: string; body: string }): Promise<void>;
  /**
   * Check current permission status
   */
  checkPermissions(): Promise<PermissionStatus>;

  /**
   * Request permissions for notifications
   */
  requestPermissions(): Promise<PermissionStatus>;

  /**
   * Add listener for alarm ring events
   */
  addListener(
    eventName: 'alarmRang',
    listenerFunc: (data: { alarmId: number }) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Add listener for alarm stop events
   */
  addListener(
    eventName: 'alarmStopped',
    listenerFunc: (data: { alarmId: number }) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Remove all listeners for this plugin
   */
  removeAllListeners(): Promise<void>;
}

export interface PermissionStatus {
  /**
   * Permission state for notifications
   */
  notifications: PermissionState;
}

export interface AlarmSettings {
  /**
   * Unique identifier of the alarm
   */
  id: number;

  /**
   * The date and time when the alarm should ring (ISO string)
   */
  dateTime: string;

  /**
   * The path to audio asset for the alarm ringtone
   */
  assetAudioPath: string;

  /**
   * Volume settings for the alarm
   */
  volumeSettings: VolumeSettings;

  /**
   * Notification settings for the alarm
   */
  notificationSettings: NotificationSettings;

  /**
   * Whether to loop the audio indefinitely
   * @default true
   */
  loopAudio?: boolean;

  /**
   * Whether to vibrate when alarm rings
   * @default true
   */
  vibrate?: boolean;

  /**
   * Whether to show warning notification when app is killed
   * @default true
   */
  warningNotificationOnKill?: boolean;

  /**
   * Whether to use full screen intent on Android
   * @default true
   */
  androidFullScreenIntent?: boolean;

  /**
   * Whether to allow alarm overlap
   * @default false
   */
  allowAlarmOverlap?: boolean;

  /**
   * Whether to enable background audio on iOS
   * @default true
   */
  iOSBackgroundAudio?: boolean;

  /**
   * Whether to stop alarm when Android task is terminated
   * @default true
   */
  androidStopAlarmOnTermination?: boolean;

  /**
   * Optional payload data
   */
  payload?: string;
}

export interface VolumeSettings {
  /**
   * System volume level (0.0 to 1.0)
   */
  volume?: number;

  /**
   * Duration over which to fade the alarm (in milliseconds)
   */
  fadeDuration?: number;

  /**
   * Volume fade steps for custom fade patterns
   */
  fadeSteps?: VolumeFadeStep[];

  /**
   * Whether to enforce the volume setting
   * @default false
   */
  volumeEnforced?: boolean;
}

export interface VolumeFadeStep {
  /**
   * Time in milliseconds from alarm start
   */
  time: number;

  /**
   * Volume level at this time (0.0 to 1.0)
   */
  volume: number;
}

export interface NotificationSettings {
  /**
   * Title of the alarm notification
   */
  title: string;

  /**
   * Body of the alarm notification
   */
  body: string;

  /**
   * Text for the stop button (null to hide button)
   */
  stopButton?: string;

  /**
   * Icon name for the notification (Android only)
   */
  icon?: string;

  /**
   * Color of the notification icon as hex string (Android only)
   */
  iconColor?: string;
}

export interface PluginListenerHandle {
  remove(): Promise<void>;
}