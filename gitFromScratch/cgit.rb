#! /usr/bin/env ruby
require 'byebug'

require 'fileutils'
require 'pathname'
require_relative './workspace'
require_relative './database'
require_relative './lib/database/blob'
require_relative './entry'
require_relative './lib/database/tree'
require_relative './lib/database/author'
require_relative './lib/database/commit'
require_relative './refs'
require_relative './lockfile'

command = ARGV.shift

case command
when 'init'
  path = ARGV.fetch(0, Dir.getwd)

  root_path = Pathname.new(File.expand_path(path))
  git_path = root_path.join('.git')

  ['objects', 'refs'].each do |dir|
    begin
      FileUtils.mkdir_p(git_path.join(dir))
    rescue Errno::EACCES => error
      $stderr.puts "fatal: #{error.message}"
      exit 1
    end
  end

  puts "Initialized empty cgit repository in #{git_path}"
  exit 0
when 'commit'
  root_path = Pathname.new(Dir.getwd)
  git_path = root_path.join(".git")
  db_path = git_path.join("objects")

  workspace = Workspace.new(root_path)
  db = Database.new(db_path)
  refs = Refs.new(git_path)

  entries = workspace.list_files.map do |path|
    data = workspace.read_file(path)
    blob = Blob.new(data)

    db.store(blob)

    stat = workspace.stat_file(path)
    Entry.new(path, blob.oid, stat)
  end

  root = Tree.build(entries)
  root.traverse { |tree| db.store(tree) }

  parent = refs.read_head
  name = ENV.fetch('CGIT_AUTHOR_NAME')
  email = ENV.fetch('CGIT_AUTHOR_EMAIL')
  author = Author.new(name, email, Time.now)
  message = $stdin.read

  commit = Commit.new(parent, root.oid, author, message)
  db.store(commit)
  refs.update_head(commit.oid)

  is_root = parent.nil? ? '(root-commit)' : ''

  File.open(git_path.join('HEAD'), File::WRONLY | File::CREAT) do |file|
    file.puts(commit.oid)
  end

  puts "[#{is_root}#{commit.oid}] #{message.lines.first}"
  exit 0
else
  $stderr.puts "cgit: '#{command}' is not a cgit command."
  exit 1
end