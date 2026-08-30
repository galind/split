import AudioToolbox
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.content.categoryIdentifier
      == NotificationScheduler.previewCategoryIdentifier
    {
      let userInfo = notification.request.content.userInfo
      if let filename = userInfo[NotificationScheduler.previewBundledSoundKey] as? String,
        playBundledAlert(named: filename)
      {
        completionHandler([.banner])
      } else if userInfo[NotificationScheduler.previewHasNoSoundKey] as? Bool == true {
        completionHandler([.banner])
      } else {
        completionHandler([.banner, .sound])
      }
    } else {
      completionHandler([.sound])
    }
  }

  private func playBundledAlert(named filename: String) -> Bool {
    let name = (filename as NSString).deletingPathExtension
    let extensionName = (filename as NSString).pathExtension
    guard let url = Bundle.main.url(forResource: name, withExtension: extensionName) else {
      return false
    }

    var soundID: SystemSoundID = 0
    guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError
    else {
      return false
    }

    AudioServicesPlayAlertSoundWithCompletion(soundID) {
      AudioServicesDisposeSystemSoundID(soundID)
    }
    return true
  }
}
