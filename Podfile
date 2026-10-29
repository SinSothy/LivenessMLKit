platform :ios, '15.0'

target 'LivenessMlKit' do
  use_frameworks!

  # Google ML Kit Face Detection
  pod 'GoogleMLKit/FaceDetection', '~> 6.0.0'

  # TensorFlow Lite for running .tflite models
  pod 'TensorFlowLiteSwift', '~> 2.14.0'
end

# Automatically elevate all pod targets to iOS 15.0 minimum and disable User Script Sandboxing
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
    end
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      end
    end
    aggregate_target.user_project.save
  end
end