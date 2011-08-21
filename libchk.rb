#!/usr/bin/env ruby
# -*- ruby -*-
#
# libchk - checks shared library links of binaries
#
# Copyright (c) 2001-2004, 2009, 2011 Akinori MUSHA
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $Id$

if RUBY_VERSION < "1.8.7"
  STDERR.puts "Ruby 1.8.7 or later is required."
  exit 255
end

MYVERSION = "1.10.1"
MYNAME = File.basename($0)

require 'optparse'
require 'find'
require 'pathname'
require 'shellwords'

LDCONFIG_CMD = '/sbin/ldconfig -elf'
OBJDUMP_CMD = '/usr/bin/objdump'
BRANDELF_CMD = '/usr/bin/brandelf'

def init_global
  $detailed = false
  $strict = false

  $localbase = ENV['LOCALBASE'] || '/usr/local'
  $x11base = ENV['X11BASE'] || '/usr/X11R6'

  $bindirs = [
    "/bin",
    "/sbin",
    "/usr/bin",
    "/usr/games",
    "/usr/libexec",
    "/usr/sbin",
    "#{$localbase}/bin",
    "#{$localbase}/libexec",
    "#{$localbase}/sbin",
    "#{$x11base}/bin",
    "#{$x11base}/libexec",
    "#{$x11base}/sbin",
  ]

  $exclude_dirs = []
end

def main(argv)
  usage = <<-"EOF"
usage: #{MYNAME} [-sv] [-x dir] [dir ...]
  EOF

  banner = <<-"EOF"
#{MYNAME} - checks shared library links of binaries
  version #{MYVERSION}

#{usage}
  EOF

  OptionParser.new(banner) do |opts|
    opts.def_option("-h", "--help", "Show this message") {
      print opts
      exit 0
    }

    opts.def_option("-s", "--strict", "Perform stricter checks") {
      |$strict|
    }

    opts.def_option("-v", "--verbose", "Make a detailed report") {
      |$detailed|
    }

    opts.def_option("-x", "--exclude=DIR", "Exclude the given directory") {
      |dir|
      $exclude_dirs << dir
    }

    opts.def_tail_option '
Environment Variables [default]:
    PATH             command search path
    LOCALBASE        local base directory [/usr/local]
    X11BASE          X11 base directory [/usr/X11R6]'

    begin
      init_global

      opts.order!(argv)
    rescue OptionParser::ParseError => e
      STDERR.puts "#{MYNAME}: #{e}", usage
      exit 64
    end
  end

  $libdirs, $libtable = scan_libs

  $librevtable = {}

  $libtable.each_value { |file|
    $librevtable[file] = nil
  }

  dirs = (ENV['PATH'].split(':') | argv | $bindirs | $libdirs).map { |dir|
    dir.dup
  }

  compact_dirs!(dirs)

  compact_dirs!($exclude_dirs)

  # ignore exclude directories that are irrelevant
  $exclude_dirs.reject! { |xdir|
    !dirs.detect { |dir|
      dir_include?(dir, xdir) || dir_include?(xdir, dir)
    }
  }

  # exclude directories that are under any of exclude directories
  dirs.reject! { |dir|
    $exclude_dirs.detect { |xdir|
      dir_include?(xdir, dir)
    }
  }

  # ignore exclude directories that are now irrelevant
  $exclude_dirs.reject! { |xdir|
    !dirs.detect { |dir|
      dir_include?(dir, xdir)
    }
  }

  # the directory list and the exclude list are now optimized

  puts "Will look into:"

  dirs.each { |dir|
    puts "\t#{dir}"
  }

  if !$exclude_dirs.empty?
    puts "Except:"

    $exclude_dirs.each { |dir|
      puts "\t#{dir}"
    }
  end

  Find.find(*dirs) { |file|
    xdir = nil

    if $exclude_dirs.detect { |xdir| dir_include?(xdir, file) }
      $exclude_dirs.delete(xdir)
      Find.prune
    end

    next if !binary?(file)

    unresolvable = []

    get_libdep(file).each { |lib, libpath|
      if libpath
	if $detailed
	  ($librevtable[libpath] ||= []).push(file)
	else
	  $librevtable[libpath] = true
	end
      else
	unresolvable << lib
      end
    }

    if !unresolvable.empty?
      puts "Unresolvable link(s) found in: #{file}"

      unresolvable.each { |lib|
	puts "\t#{lib}"
      }
    end
  }

  libfiles = $librevtable.keys
  libfiles.sort!

  libfiles.each { |libfile|
    referers = $librevtable[libfile]

    if !referers
      puts "Unreferenced library: #{libfile}"
    elsif $detailed
      referers.sort!

      puts "Binaries that are linked with: #{libfile}"
      referers.each { |referer|
	puts "\t#{referer}"
      }
    end
  }
end

def scan_libs
  libdirs = nil

  libtable = {}

  `#{LDCONFIG_CMD} -r`.each { |line|
    line.strip!

    case line
    when /^search directories:\s*(.*)/
      libdirs = normalize_dirs!($1.split(':'))
    when %r"^\d+:-l.*\s+=>\s+(/.*/([^/]+))"
      path, filename = $1, $2

      # handle sequences of /'s (tr_s is not multibyte-aware, hence gsub)
      path.gsub!(%r"//+", '/')

      libtable[filename] = path
    end
  }

  [libdirs, libtable]
end

def dead_link?(file)
  File.symlink?(file) && !File.exist?(file)
end

def binary?(file)
  if !File.readable?(file)
    STDERR.puts "Unreadable file or directory: #{file}"
    return false
  end

  File.symlink?(file) || !File.file?(file) and return false

  check_elfbrand(file)
end

def check_elfbrand(file)
  /^File '.*' is of brand 'FreeBSD' \(9\)/ =~
    `#{BRANDELF_CMD} #{file.shellescape} 2>/dev/null`
end

def dir_include?(dir1, dir2)
  return true if dir1 == '/'

  len = dir1.size

  (dir2[len] == ?/ && dir2[0...len] == dir1) || (dir1 == dir2)
end

def normalize_dir!(dir)
  # handle sequences of /'s (tr_s is not multibyte-aware, hence gsub)
  dir.gsub!(%r"//+", '/')
  dir.replace(File.expand_path(dir))

  return dir if dir == '/'

  dir.chomp!('/')

  if File.directory?(dir)
    dir
  else
    nil
  end
end

def normalize_dirs!(dirs)
  dirs.reject! { |dir|
    normalize_dir!(dir).nil?
  }
  dirs
end

def locate_file(file, dirs)
  if file[0] == ?/
    return File.exist?(file) ? file : nil
  end

  dirs.each { |dir|
    path = File.join(dir, file)

    File.exist?(path) and return path
  }

  nil
end

def get_libdep(file)
  dep = []
  rpath = []

  `#{OBJDUMP_CMD} -p #{file.shellescape} 2>/dev/null`.each { |line|
    line.strip!

    case line
    when /^NEEDED\s+(.*)/
      dep << $1
    when /^RPATH\s+(.*)/
      rpath = normalize_dirs!($1.split(':'))
    end
  }

  deptable = {}

  all_rpath = rpath | $libdirs

  unless $strict
    all_rpath |= [File.dirname(file)]
  end

  dep.each { |lib|
    if $libtable.key?(lib)
      deptable[lib] = locate_file(lib, rpath) || $libtable[lib]
    else
      deptable[lib] = locate_file(lib, all_rpath)
    end
  }

  deptable
end

def compact_dirs!(dirs)
  normalize_dirs!(dirs)

  newdirs = dirs.group_by { |dir|
    Pathname(dir).realpath
  }.map { |realpath, ldirs|
    ldirs.first
  }

  newdirs.sort!

  prev = nil
  newdirs.reject! { |dir|
    if prev && dir_include?(prev, dir)
      true
    else
      prev = dir
      false
    end
  }

  dirs.replace(newdirs)
end

main(ARGV)

exit 0
