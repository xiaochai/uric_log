platform :ios, '17.0'

target 'UricLog' do
  pod 'UMCommon'
  pod 'UMDevice'
  pod 'UMUnionSDK'
  pod 'Google-Mobile-Ads-SDK'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
