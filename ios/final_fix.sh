#!/bin/bash

# Create a new temporary file with our modifications
awk '{
    # Replace our problematic line with a corrected version
    if ($0 ~ /ABCDEF20250308005954FEDCBA.*GoogleService-Info\.plist.*Resources.*,$/) {
        print "\t\t\t\tABCDEF20250308005954FEDCBA /* GoogleService-Info.plist in Resources */,";
    }
    else {
        print $0;
    }
}' Runner.xcodeproj/project.pbxproj > Runner.xcodeproj/project.pbxproj.new

# Replace the original file with our fixed version
mv Runner.xcodeproj/project.pbxproj.new Runner.xcodeproj/project.pbxproj
