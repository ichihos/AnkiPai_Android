#!/usr/bin/env ruby

# Script to fix issues with FirebaseAnalytics module map file
# This script addresses the missing closing brace issue
# Run this after pod install with: ruby fix_firebase_modulemap.rb

require 'fileutils'

# Search for FirebaseAnalytics modulemap files in both Pods directory and build directory
modulemap_paths = Dir.glob([
  "./Pods/**/FirebaseAnalytics.framework/Modules/module.modulemap", 
  "../build/**/FirebaseAnalytics.framework/Modules/module.modulemap",
  "../build/ios/Debug-iphonesimulator/XCFrameworkIntermediates/FirebaseAnalytics/**/FirebaseAnalytics.framework/Modules/module.modulemap"
])

if modulemap_paths.empty?
  puts "No FirebaseAnalytics modulemap files found"
  exit 0
end

puts "Found #{modulemap_paths.length} modulemap files to check"

modulemap_paths.each do |modulemap_path|
  puts "Checking #{modulemap_path}"
  
  begin
    content = File.read(modulemap_path)
    original_content = content.dup
    
    # Check if the file is missing a closing brace
    if !content.strip.end_with?("}")
      puts "  Adding missing closing brace"
      content = content.strip + "\n}"
    end
    
    # Fix incomplete module * export statement if present
    if content.include?("module *") && !content.include?("module * { export * }")
      puts "  Fixing incomplete module export"
      content = content.gsub(/module \* \{ export \*$/, "module * { export * }")
    end
    
    # Only write if we made changes
    if content != original_content
      puts "  Writing fixed content to #{modulemap_path}"
      File.write(modulemap_path, content)
    else
      puts "  No changes needed"
    end
  rescue => e
    puts "  Error processing #{modulemap_path}: #{e.message}"
  end
end

puts "Finished checking all modulemap files"
