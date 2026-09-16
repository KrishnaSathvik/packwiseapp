#!/usr/bin/env ruby
# Helper: add a new Swift source file to PackWise.xcodeproj, under a given
# group path, compiled into a given target. Used during Phase 8 to register
# new files the plan creates (project uses individually-referenced files,
# not synchronized folder groups).
require 'xcodeproj'

project_path = 'PackWise.xcodeproj'
file_path = ARGV[0]       # e.g. "PackWiseTests/PersistenceTests.swift"
group_path = ARGV[1]      # e.g. "PackWiseTests" or "PackWise/Domain/Packing"
target_name = ARGV[2]     # e.g. "PackWiseTests" or "PackWise"

abort "usage: add_file_to_project.rb <file_path> <group_path> <target_name>" unless file_path && group_path && target_name

project = Xcodeproj::Project.open(project_path)

group = project.main_group
group_path.split('/').each do |segment|
  group = group[segment] || group.new_group(segment)
end

basename = File.basename(file_path)
existing = group.children.find { |c| c.respond_to?(:display_name) && c.display_name == basename }
if existing
  puts "Already present in group: #{basename}"
else
  file_ref = group.new_reference(file_path)
  target = project.targets.find { |t| t.name == target_name }
  abort "target not found: #{target_name}" unless target
  target.add_file_references([file_ref])
  puts "Added #{basename} to group #{group_path} and target #{target_name}"
end

project.save
