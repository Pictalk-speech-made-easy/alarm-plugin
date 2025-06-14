# alarm

This plugins allow Capacitor to manage alarms. Heavily (almost entirely) inspired by the [Alarm](https://github.com/gdelataillade/alarm) Flutter plugin.

## Install

```bash
npm install alarm
npx cap sync
```

## API

<docgen-index>

* [`setAlarm(...)`](#setalarm)
* [`stopAlarm(...)`](#stopalarm)
* [`stopAll()`](#stopall)
* [`isRinging(...)`](#isringing)
* [`getAlarms()`](#getalarms)
* [`setWarningNotificationOnKill(...)`](#setwarningnotificationonkill)
* [`checkPermissions()`](#checkpermissions)
* [`requestPermissions()`](#requestpermissions)
* [`addListener('alarmRang', ...)`](#addlisteneralarmrang-)
* [`addListener('alarmStopped', ...)`](#addlisteneralarmstopped-)
* [`removeAllListeners()`](#removealllisteners)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### setAlarm(...)

```typescript
setAlarm(options: { alarmSettings: AlarmSettings; }) => any
```

Set an alarm with the specified settings

| Param         | Type                                                                        |
| ------------- | --------------------------------------------------------------------------- |
| **`options`** | <code>{ alarmSettings: <a href="#alarmsettings">AlarmSettings</a>; }</code> |

**Returns:** <code>any</code>

--------------------


### stopAlarm(...)

```typescript
stopAlarm(options: { alarmId: number; }) => any
```

Stop a specific alarm by ID

| Param         | Type                              |
| ------------- | --------------------------------- |
| **`options`** | <code>{ alarmId: number; }</code> |

**Returns:** <code>any</code>

--------------------


### stopAll()

```typescript
stopAll() => any
```

Stop all active alarms

**Returns:** <code>any</code>

--------------------


### isRinging(...)

```typescript
isRinging(options: { alarmId?: number; }) => any
```

Check if an alarm is currently ringing

| Param         | Type                               |
| ------------- | ---------------------------------- |
| **`options`** | <code>{ alarmId?: number; }</code> |

**Returns:** <code>any</code>

--------------------


### getAlarms()

```typescript
getAlarms() => any
```

Get all scheduled alarms

**Returns:** <code>any</code>

--------------------


### setWarningNotificationOnKill(...)

```typescript
setWarningNotificationOnKill(options: { title: string; body: string; }) => any
```

Set warning notification when app is killed

| Param         | Type                                          |
| ------------- | --------------------------------------------- |
| **`options`** | <code>{ title: string; body: string; }</code> |

**Returns:** <code>any</code>

--------------------


### checkPermissions()

```typescript
checkPermissions() => any
```

Check current permission status

**Returns:** <code>any</code>

--------------------


### requestPermissions()

```typescript
requestPermissions() => any
```

Request permissions for notifications

**Returns:** <code>any</code>

--------------------


### addListener('alarmRang', ...)

```typescript
addListener(eventName: 'alarmRang', listenerFunc: (data: { alarmId: number; }) => void) => any
```

Add listener for alarm ring events

| Param              | Type                                                 |
| ------------------ | ---------------------------------------------------- |
| **`eventName`**    | <code>'alarmRang'</code>                             |
| **`listenerFunc`** | <code>(data: { alarmId: number; }) =&gt; void</code> |

**Returns:** <code>any</code>

--------------------


### addListener('alarmStopped', ...)

```typescript
addListener(eventName: 'alarmStopped', listenerFunc: (data: { alarmId: number; }) => void) => any
```

Add listener for alarm stop events

| Param              | Type                                                 |
| ------------------ | ---------------------------------------------------- |
| **`eventName`**    | <code>'alarmStopped'</code>                          |
| **`listenerFunc`** | <code>(data: { alarmId: number; }) =&gt; void</code> |

**Returns:** <code>any</code>

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => any
```

Remove all listeners for this plugin

**Returns:** <code>any</code>

--------------------


### Interfaces


#### AlarmSettings

| Prop                                | Type                                                                  | Description                                               | Default            |
| ----------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- | ------------------ |
| **`id`**                            | <code>number</code>                                                   | Unique identifier of the alarm                            |                    |
| **`dateTime`**                      | <code>string</code>                                                   | The date and time when the alarm should ring (ISO string) |                    |
| **`assetAudioPath`**                | <code>string</code>                                                   | The path to audio asset for the alarm ringtone            |                    |
| **`volumeSettings`**                | <code><a href="#volumesettings">VolumeSettings</a></code>             | Volume settings for the alarm                             |                    |
| **`notificationSettings`**          | <code><a href="#notificationsettings">NotificationSettings</a></code> | Notification settings for the alarm                       |                    |
| **`loopAudio`**                     | <code>boolean</code>                                                  | Whether to loop the audio indefinitely                    | <code>true</code>  |
| **`vibrate`**                       | <code>boolean</code>                                                  | Whether to vibrate when alarm rings                       | <code>true</code>  |
| **`warningNotificationOnKill`**     | <code>boolean</code>                                                  | Whether to show warning notification when app is killed   | <code>true</code>  |
| **`androidFullScreenIntent`**       | <code>boolean</code>                                                  | Whether to use full screen intent on Android              | <code>true</code>  |
| **`allowAlarmOverlap`**             | <code>boolean</code>                                                  | Whether to allow alarm overlap                            | <code>false</code> |
| **`iOSBackgroundAudio`**            | <code>boolean</code>                                                  | Whether to enable background audio on iOS                 | <code>true</code>  |
| **`androidStopAlarmOnTermination`** | <code>boolean</code>                                                  | Whether to stop alarm when Android task is terminated     | <code>true</code>  |
| **`payload`**                       | <code>string</code>                                                   | Optional payload data                                     |                    |


#### VolumeSettings

| Prop                 | Type                 | Description                                             | Default            |
| -------------------- | -------------------- | ------------------------------------------------------- | ------------------ |
| **`volume`**         | <code>number</code>  | System volume level (0.0 to 1.0)                        |                    |
| **`fadeDuration`**   | <code>number</code>  | Duration over which to fade the alarm (in milliseconds) |                    |
| **`fadeSteps`**      | <code>{}</code>      | Volume fade steps for custom fade patterns              |                    |
| **`volumeEnforced`** | <code>boolean</code> | Whether to enforce the volume setting                   | <code>false</code> |


#### VolumeFadeStep

| Prop         | Type                | Description                            |
| ------------ | ------------------- | -------------------------------------- |
| **`time`**   | <code>number</code> | Time in milliseconds from alarm start  |
| **`volume`** | <code>number</code> | Volume level at this time (0.0 to 1.0) |


#### NotificationSettings

| Prop             | Type                | Description                                                 |
| ---------------- | ------------------- | ----------------------------------------------------------- |
| **`title`**      | <code>string</code> | Title of the alarm notification                             |
| **`body`**       | <code>string</code> | Body of the alarm notification                              |
| **`stopButton`** | <code>string</code> | Text for the stop button (null to hide button)              |
| **`icon`**       | <code>string</code> | Icon name for the notification (Android only)               |
| **`iconColor`**  | <code>string</code> | Color of the notification icon as hex string (Android only) |


#### PermissionStatus

| Prop                | Type                                                        | Description                        |
| ------------------- | ----------------------------------------------------------- | ---------------------------------- |
| **`notifications`** | <code><a href="#permissionstate">PermissionState</a></code> | Permission state for notifications |


#### PluginListenerHandle

| Prop         | Type                      |
| ------------ | ------------------------- |
| **`remove`** | <code>() =&gt; any</code> |


### Type Aliases


#### PermissionState

<code>'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'</code>

</docgen-api>
