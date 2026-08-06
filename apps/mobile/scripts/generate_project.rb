#!/usr/bin/env ruby

require "xcodeproj"

project_path = File.expand_path("../AgentBox.xcodeproj", __dir__)
abort "AgentBox.xcodeproj already exists." if File.exist?(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2630"
project.root_object.attributes["LastUpgradeCheck"] = "2630"

app_target = project.new_target(:application, "AgentBox", :ios, "17.0")
test_target = project.new_target(:unit_test_bundle, "AgentBoxTests", :ios, "17.0")
ui_test_target = project.new_target(:ui_test_bundle, "AgentBoxUITests", :ios, "17.0")
test_target.add_dependency(app_target)
ui_test_target.add_dependency(app_target)

app_group = project.main_group.new_group("AgentBox", "AgentBox")
test_group = project.main_group.new_group("AgentBoxTests", "AgentBoxTests")
ui_test_group = project.main_group.new_group("AgentBoxUITests", "AgentBoxUITests")

def add_tree(group, directory, target)
  Dir.children(directory).sort.each do |entry|
    next if entry.start_with?(".")

    path = File.join(directory, entry)
    if File.directory?(path) && !entry.end_with?(".xcassets", ".icon")
      add_tree(group.new_group(entry, entry), path, target)
      next
    end

    reference = group.new_file(entry)
    if entry.end_with?(".swift", ".metal")
      target.add_file_references([reference])
    elsif entry.end_with?(".xcassets", ".icon")
      target.resources_build_phase.add_file_reference(reference)
    end
  end
end

add_tree(app_group, File.expand_path("../AgentBox", __dir__), app_target)
add_tree(test_group, File.expand_path("../AgentBoxTests", __dir__), test_target)
add_tree(ui_test_group, File.expand_path("../AgentBoxUITests", __dir__), ui_test_target)

project.build_configurations.each do |configuration|
  configuration.build_settings["CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED"] = "YES"
  configuration.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

app_target.build_configurations.each do |configuration|
  configuration.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  configuration.build_settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  configuration.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  configuration.build_settings["CODE_SIGN_ENTITLEMENTS"] = "AgentBox/AgentBox.entitlements"
  configuration.build_settings["CURRENT_PROJECT_VERSION"] = "2"
  configuration.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  configuration.build_settings["INFOPLIST_FILE"] = "AgentBox/Resources/Info.plist"
  configuration.build_settings["MARKETING_VERSION"] = "0.1.0"
  configuration.build_settings["OTHER_LDFLAGS"] = "$(inherited) -lsqlite3"
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "cc.agentboxes"
  configuration.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  configuration.build_settings["SWIFT_VERSION"] = "5.0"
  configuration.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
end

test_target.build_configurations.each do |configuration|
  configuration.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
  configuration.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  configuration.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "cc.agentboxes.tests"
  configuration.build_settings["SWIFT_VERSION"] = "5.0"
  configuration.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/AgentBox.app/AgentBox"
end

ui_test_target.build_configurations.each do |configuration|
  configuration.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  configuration.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "cc.agentboxes.uitests"
  configuration.build_settings["SWIFT_VERSION"] = "5.0"
  configuration.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
  configuration.build_settings["TEST_TARGET_NAME"] = "AgentBox"
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.add_test_target(ui_test_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, "AgentBox", true)

project.save
puts "Generated #{project_path}"
