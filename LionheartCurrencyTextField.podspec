Pod::Spec.new do |s|
  s.name             = 'LionheartCurrencyTextField'
  s.version          =  "1.0.0"
  s.summary          = 'A text field that formats currency values'

  s.description      = <<-DESC
LionheartCurrencyTextField is a drop-in replacement for UITextField that
displays currency values the way you'd expect it to. It's based on the user's
current locale, so in the US, typing "12345.12" will output "$12,345.12".

See the GitHub project for more details.
                       DESC

  s.homepage         = 'https://github.com/lionheart/LionheartCurrencyTextField'
  s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author           = { 'Dan Loewenherz' => 'dan@lionheartsw.com' }
  s.source           = { :git => 'https://github.com/lionheart/LionheartCurrencyTextField.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/lionheartsw'

  s.pod_target_xcconfig = {
    'SWIFT_VERSION' => '3.0'
  }

  s.ios.deployment_target = '9.0'
  s.source_files = 'LionheartCurrencyTextField/Classes/**/*'
  s.dependency 'LionheartExtensions', '~> 2.0'
end
