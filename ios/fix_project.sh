#!/bin/bash

# Read the file and make changes
awk '
# When we find the PBXBuildFile section, add our new entry
/\/\* Begin PBXBuildFile section \*\//{
    print $0;
    print "\t\tABCDEF20250308005954FEDCBA /* GoogleService-Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = 8008DFD4BF7ADCE597E1D454 /* GoogleService-Info.plist */; };";
    next;
}

# When we find the Main.storyboard in Resources entry, add our new entry after it
/97C146FC1CF9000F007C117D \/\* Main.storyboard in Resources \*\//{
    print $0;
    print "\t\t\t\tABCDEF20250308005954FEDCBA /* GoogleService-Info.plist in Resources */,";
    next;
}

# Print all other lines unchanged
{print}
' Runner.xcodeproj/project.pbxproj > Runner.xcodeproj/project.pbxproj.new

# Replace the original file with the new one
mv Runner.xcodeproj/project.pbxproj.new Runner.xcodeproj/project.pbxproj
