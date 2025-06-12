import { WebPlugin } from '@capacitor/core';
import type { AlarmPlugin, AlarmSettings, PluginListenerHandle } from './definitions';

export class AlarmWeb extends WebPlugin implements AlarmPlugin {
  async init(): Promise<void> {
    throw this.unimplemented('Not implemented on web.');
  }

  async setAlarm(options: { alarmSettings: AlarmSettings }): Promise<void> {
    console.log('setAlarm', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async stopAlarm(options: { alarmId: number }): Promise<void> {
    console.log('stopAlarm', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async stopAll(): Promise<void> {
    throw this.unimplemented('Not implemented on web.');
  }

  async isRinging(options: { alarmId?: number }): Promise<{ isRinging: boolean }> {
    console.log('isRinging', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async getAlarms(): Promise<{ alarms: AlarmSettings[] }> {
    throw this.unimplemented('Not implemented on web.');
  }

  async setWarningNotificationOnKill(options: { title: string; body: string }): Promise<void> {
    console.log('setWarningNotificationOnKill', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async checkAlarm(): Promise<void> {
    throw this.unimplemented('Not implemented on web.');
  }

  async addListener(
    eventName: 'alarmRang' | 'alarmStopped',
    listenerFunc: (data: { alarmId: number }) => void,
  ): Promise<PluginListenerHandle> {
    return super.addListener(eventName, listenerFunc);
  }

  async removeAllListeners(): Promise<void> {
    super.removeAllListeners();
  }
}