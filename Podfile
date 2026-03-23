use_modular_headers!
inhibit_all_warnings!

platform :ios, '15.6'
source 'https://cdn.cocoapods.org/'

target 'CH Drone 2' do
  use_frameworks!

  pod 'DJI-SDK-iOS', '~> 4.15'
  pod 'DJIFlySafeDatabaseResource', '~> 01.00.01.18'
  pod 'DJI-UXSDK-iOS-Beta', '~> 0.4.2'
end

target 'CHDroneTests' do
  use_frameworks!

  pod 'DJI-SDK-iOS', '~> 4.15'
  pod 'DJIFlySafeDatabaseResource', '~> 01.00.01.18'
  pod 'DJI-UXSDK-iOS-Beta', '~> 0.4.2'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.6
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.6'
      end
    end
  end
end
