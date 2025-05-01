#!/usr/bin/env ruby

# Script to fix duplicate frameworks in Xcode projects
# This helps resolve the common "Multiple commands produce..." error in Flutter iOS builds

begin
  require 'xcodeproj'
rescue LoadError
  puts "The 'xcodeproj' gem is required but not installed."
  puts "Installing 'xcodeproj' gem..."
  system("gem install xcodeproj")
  require 'xcodeproj'
end

puts "Looking for Xcode project..."
project_path = Dir.glob("*.xcodeproj").first

if project_path.nil?
  puts "Error: No Xcode project found in the current directory."
  exit 1
end

puts "Opening project: #{project_path}"
project = Xcodeproj::Project.open(project_path)

# Track if we made any changes
changes_made = false

project.targets.each do |target|
  puts "Processing target: #{target.name}"
  
  # Find the 'Embed Frameworks' build phase
  embed_frameworks_phase = target.build_phases.find do |phase|
    phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && 
    phase.name == 'Embed Frameworks'
  end
  
  if embed_frameworks_phase.nil?
    puts "  No 'Embed Frameworks' build phase found in target #{target.name}. Skipping."
    next
  end
  
  puts "  Found 'Embed Frameworks' build phase with #{embed_frameworks_phase.files.count} files"
  
  # Create a hash to track unique frameworks by destination path
  unique_frameworks = {}
  duplicates_found = false
  
  embed_frameworks_phase.files.each do |file|
    next if file.file_ref.nil? || file.file_ref.path.nil?
    
    framework_path = file.file_ref.path
    framework_name = File.basename(framework_path)
    
    if unique_frameworks[framework_name].nil?
      unique_frameworks[framework_name] = file
      puts "  Keeping: #{framework_name}"
    else
      puts "  Removing duplicate: #{framework_name}"
      embed_frameworks_phase.remove_build_file(file)
      duplicates_found = true
      changes_made = true
    end
  end
  
  if duplicates_found
    puts "  Removed duplicate frameworks from target: #{target.name}"
  else
    puts "  No duplicates found in target: #{target.name}"
  end
end

if changes_made
  puts "Saving changes to project..."
  project.save
  puts "✅ Project saved. Duplicate frameworks have been removed."
else
  puts "No duplicate frameworks were found. No changes made."
end

puts "Done."

#!/usr/bin/env ruby

# Check if xcodeproj gem is installed, install if not
begin
  require 'xcodeproj'
rescue LoadError
  puts "xcodeproj gem not found. Installing..."
  system('gem install xcodeproj')
  require 'xcodeproj'
end

puts "Looking for Xcode project files..."
# Find the .xcodeproj file in the current directory
xcodeproj_paths = Dir.glob("*.xcodeproj")

if xcodeproj_paths.empty?
  puts "No Xcode project found in the current directory!"
  exit 1
end

xcodeproj_path = xcodeproj_paths.first
puts "Found Xcode project: #{xcodeproj_path}"

# Open the Xcode project
project = Xcodeproj::Project.open(xcodeproj_path)
puts "Successfully opened the project"

# Counter for tracking changes
duplicates_removed = 0

# Process each target in the project
project.targets.each do |target|
  puts "Processing target: #{target.name}"
  
  # Find the 'Embed Frameworks' build phase in the target
  embed_frameworks_phase = target.build_phases.find do |phase|
    phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && 
    phase.name == 'Embed Frameworks'
  end
  
  if embed_frameworks_phase.nil?
    puts "No 'Embed Frameworks' build phase found for target #{target.name}, skipping..."
    next
  end
  
  puts "Found 'Embed Frameworks' build phase with #{embed_frameworks_phase.files.count} framework entries"
  
  # Create a hash to store unique frameworks by their destination paths
  unique_frameworks = {}
  frameworks_to_remove = []
  
  # Process each file reference in the build phase
  embed_frameworks_phase.files.each do |build_file|
    next if build_file.file_ref.nil? || build_file.file_ref.path.nil?
    
    # Use the path as a unique identifier
    path = build_file.file_ref.path
    
    # Check if this framework has already been processed
    if unique_frameworks[path]
      puts "  Found duplicate entry for framework: #{path}"
      frameworks_to_remove << build_file
      duplicates_removed += 1
    else
      unique_frameworks[path] = build_file
    end
  end
  
  # Remove the duplicate frameworks
  frameworks_to_remove.each do |build_file|
    embed_frameworks_phase.files.delete(build_file)
  end
  
  puts "  Removed #{frameworks_to_remove.count} duplicate entries from target #{target.name}"
end

if duplicates_removed > 0
  # Save the project
  project.save
  puts "Project saved successfully! Removed #{duplicates_removed} duplicate framework entries."
else
  puts "No duplicate frameworks found. Project was not modified."
end

puts "Script completed successfully!"

