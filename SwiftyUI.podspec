#
#  Be sure to run `pod spec lint SwiftyUI.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  s.name         = "SwiftyUI"
  s.version      = "3.0.0"
  s.summary      = "High performance and lightweight UI."

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  s.description  = <<-DESC
  High performance and lightweight (one class per UI component) UIView, UIImage, UIImageView, UILabel, UIButton and more.
                   DESC

  s.homepage     = "https://github.com/haoking/SwiftyUI"
  # s.screenshots  = "www.example.com/screenshots_1.gif", "www.example.com/screenshots_2.gif"


  # ―――  Spec License  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Licensing your code is important. See http://choosealicense.com for more info.
  #  CocoaPods will detect a license file if there is a named LICENSE*
  #  Popular ones are 'MIT', 'BSD' and 'Apache License, Version 2.0'.
  #

  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  # s.license      = { :type => "MIT", :file => "FILE_LICENSE" }


  # ――― Author Metadata  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the authors of the library, with email addresses. Email addresses
  #  of the authors are extracted from the SCM log. E.g. $ git log. CocoaPods also
  #  accepts just a name if you'd rather not provide an email address.
  #
  #  Specify a social_media_url where others can refer to, for example a twitter
  #  profile URL.
  #

  s.author             = { "Haochen Wang" => "haokinus@gmail.com" }
  # Or just: s.author    = "Haochen Wang"
  # s.authors            = { "Haochen Wang" => "hoakinus@gmail.com" }
  # s.social_media_url   = "http://twitter.com/Haochen Wang"

  # ――― Platform Specifics ――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If this Pod runs only on iOS or OS X, then specify the platform and
  #  the deployment target. You can optionally include the target after the platform.
  #

  # s.platform     = :ios
  # s.platform     = :ios, "5.0"

  #  When using multiple platforms
  #  3.0.0 raised the floor from 15.0 to 18.0: the source uses Mutex and Atomic
  #  from the Synchronization module, which first shipped in iOS 18.
  s.ios.deployment_target = "18.0"
  # s.osx.deployment_target = "10.7"
  # s.watchos.deployment_target = "2.0"
  # s.tvos.deployment_target = "9.0"

  #  This is the Swift *language mode*, not the compiler version: Swift 6.4 still
  #  only has language modes up to 6. The compiler floor is Swift 6.2 (Xcode 26.0),
  #  which CocoaPods has no attribute for; Sources/SwiftyGlobal.swift turns an
  #  older compiler into a single readable #error instead.
  s.swift_version = "6.0"

  #  The same five upcoming features Package.swift enables (Swift 7 defaults; the
  #  first three are Xcode 27's defaults for new targets). They have to match:
  #  NonisolatedNonsendingByDefault changes which executor a nonisolated async
  #  function runs on, so building the pod without it would make the same source
  #  behave differently from the SwiftPM build.
  s.pod_target_xcconfig = {
    'SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT' => 'YES',
    'SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES' => 'YES',
    'SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY' => 'YES',
    'SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY' => 'YES',
    'SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT' => 'YES',
  }

  #  swift_version above is only honoured from CocoaPods 1.4.0 on. Older
  #  versions silently ignore it and build the pod with whatever Swift version
  #  the integrating project happens to use — which for this source means a
  #  wall of concurrency errors rather than a clear "unsupported tool" message.
  #  Declaring the floor turns that into an actionable error at `pod install`.
  #  Kept in sync with the "CocoaPods 1.4.0+ is required" note in README.md.
  s.cocoapods_version = ">= 1.4.0"


  # ――― Source Location ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the location from where the source should be retrieved.
  #  Supports git, hg, bzr, svn and HTTP.
  #

  s.source       = { :git => "https://github.com/haoking/SwiftyUI.git", :tag => s.version }


  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  CocoaPods is smart about how it includes source code. For source files
  #  giving a folder will include any swift, h, m, mm, c & cpp files.
  #  For header files it will include any header in the folder.
  #  Not including the public_header_files will make all headers public.
  #

  s.source_files  = 'Sources/*.swift'

  # s.ios.deployment_target = '8.0'
  # s.ios.vendored_frameworks = 'SwiftyUI.framework'
  # s.exclude_files = "Classes/Exclude"

  # s.public_header_files = "Classes/**/*.h"


  # ――― Resources ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  A list of resources included with the Pod. These are copied into the
  #  target bundle with a build phase script. Anything else will be cleaned.
  #  You can preserve files from being cleaned, please don't preserve
  #  non-essential files like tests, examples and documentation.
  #

  # s.resource  = "icon.png"
  # s.resources = "Resources/*.png"

  # s.preserve_paths = "FilesToSave", "MoreFilesToSave"


  # ――― Project Linking ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Link your library with frameworks, or libraries. Libraries do not include
  #  the lib prefix of their name.
  #

  # s.framework  = "SomeFramework"
  # s.frameworks = "SomeFramework", "AnotherFramework"

  # s.library   = "iconv"
  # s.libraries = "iconv", "xml2"


  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If your library depends on compiler flags you can set them in the xcconfig hash
  #  where they will only apply to your library. If you depend on other Podspecs
  #  you can include multiple dependencies to ensure it works.

  # s.requires_arc = true

  # s.xcconfig = { "HEADER_SEARCH_PATHS" => "$(SDKROOT)/usr/include/libxml2" }
  # s.dependency "JSONKit", "~> 1.4"

end
