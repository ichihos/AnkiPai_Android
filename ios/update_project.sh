#!/bin/bash

# Add a new entry in the PBXBuildFile section
sed -i '' '/\/\* Begin PBXBuildFile section \*\//a \
		ABCDEF20250308005954FEDCBA /* GoogleService-Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = 8008DFD4BF7ADCE597E1D454 /* GoogleService-Info.plist */; };' Runner.xcodeproj/project.pbxproj

# Add a reference to this file in the Runner's Resources build phase
sed -i '' '/97C146FC1CF9000F007C117D \/\* Main.storyboard in Resources \*\//a \
				ABCDEF20250308005954FEDCBA /* GoogleService-Info.plist in Resources */,' Runner.xcodeproj/project.pbxproj
