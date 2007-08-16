#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require 'test/gemutilities'
require 'rubygems/installer'

class Gem::Installer
  attr_accessor :options, :directory
end

class TestGemInstaller < RubyGemTestCase

  def setup
    super

    @spec = quick_gem "a"
    @gem = File.join @tempdir, "#{@spec.full_name}.gem"
    @installer = Gem::Installer.new @gem
  end

  def util_gem_dir(version = '0.0.2')
    File.join @gemhome, "gems", "a-#{version}" # HACK
  end

  def util_gem_bindir(version = '0.0.2')
    File.join util_gem_dir(version), "bin"
  end

  def util_inst_bindir
    File.join @gemhome, "bin"
  end

  def util_make_exec(version = '0.0.2')
    @spec.executables = ["my_exec"]

    FileUtils.mkdir_p util_gem_bindir(version)
    File.open File.join(util_gem_bindir(version), "my_exec"), 'w' do |f|
      f.puts "#!/bin/ruby"
    end
  end

  def test_build_extensions_none
    use_ui @ui do @installer.build_extensions util_gem_dir, @spec end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    assert !File.exist?('gem_make.out')
  end

  def test_build_extensions_extconf_bad
    @spec.extensions << 'extconf.rb'

    e = assert_raise Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions util_gem_dir, @spec
      end
    end

    assert_match(/\AERROR: Failed to build gem native extension.$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    assert_equal "\n", File.read('gem_make.out')
  ensure
    FileUtils.rm_f 'gem_make.out'
  end

  def test_build_extensions_unsupported
    @spec.extensions << nil

    e = assert_raise Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions util_gem_dir, @spec
      end
    end

    assert_match(/^No builder for extension ''$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    assert_equal "No builder for extension ''\n", File.read('gem_make.out')
  ensure
    FileUtils.rm_f 'gem_make.out'
  end

  def test_extract_files
    format = Object.new
    def format.file_entries
      [[{'size' => 7, 'mode' => 0400, 'path' => 'thefile'}, 'thefile']]
    end

    @installer.extract_files @tempdir, format

    assert_equal 'thefile', File.read(File.join(@tempdir, 'thefile'))
  end

  def test_extract_files_bad_dest
    e = assert_raise ArgumentError do
      @installer.extract_files 'somedir', nil
    end

    assert_equal 'format required to extract from', e.message
  end

  def test_extract_files_relative
    format = Object.new
    def format.file_entries
      [[{'size' => 10, 'mode' => 0644, 'path' => '../thefile'}, '../thefile']]
    end

    e = assert_raise Gem::InstallError do
      @installer.extract_files @tempdir, format
    end

    assert_equal "attempt to install file into \"../thefile\" under #{@tempdir.inspect}",
                 e.message
    assert_equal false, File.file?(File.join(@tempdir, '../thefile')),
                 "You may need to remove this file if you broke the test once"
  end

  def test_extract_files_absolute
    format = Object.new
    def format.file_entries
      [[{'size' => 8, 'mode' => 0644, 'path' => '/thefile'}, '/thefile']]
    end

    e = assert_raise Gem::InstallError do
      @installer.extract_files @tempdir, format
    end

    assert_equal 'attempt to install file into "/thefile"', e.message
    assert_equal false, File.file?(File.join('/thefile')),
                 "You may need to remove this file if you broke the test once"
  end

  def test_generate_bin_scripts
    @installer.options[:wrappers] = true
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)
    assert_equal(0100755, File.stat(installed_exec).mode) unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
    assert_match %r|ENV\['GEM_HOME'\] \|\|= '#{@gemhome}'|, wrapper
  end

  def test_generate_bin_scripts_install_dir
    @installer.options[:wrappers] = true
    @spec.executables = ["my_exec"]

    gem_dir = File.join "#{@gemhome}2", 'gems', @spec.full_name
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, "my_exec"), 'w' do |f|
      f.puts "#!/bin/ruby"
    end

    @installer.directory = gem_dir

    @installer.generate_bin @spec, "#{@gemhome}2"

    installed_exec = File.join("#{@gemhome}2", 'bin', 'my_exec')
    assert_equal true, File.exist?(installed_exec)
    assert_equal(0100755, File.stat(installed_exec).mode) unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
    assert_match %r|ENV\['GEM_HOME'\] \|\|= '#{@gemhome}2'|, wrapper
  end

  def test_generate_bin_scripts_no_execs
    @installer.options[:wrappers] = true
    @installer.generate_bin @spec, @gemhome
    assert_equal false, File.exist?(util_inst_bindir)
  end

  def test_generate_bin_scripts_no_perms
    @installer.options[:wrappers] = true
    util_make_exec

    Dir.mkdir util_inst_bindir
    File.chmod 0000, util_inst_bindir

    assert_raises Gem::FilePermissionError do
      @installer.generate_bin @spec, @gemhome
    end

  ensure
    File.chmod 0700, util_inst_bindir unless $DEBUG
  end

  def test_generate_bin_symlinks
    return if win_platform? #Windows FS do not support symlinks
    
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.symlink?(installed_exec)
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))
  end

  def test_generate_bin_symlinks_no_execs
    @installer.options[:wrappers] = false
    @installer.generate_bin @spec, @gemhome
    assert_equal false, File.exist?(util_inst_bindir)
  end

  def test_generate_bin_symlinks_no_perms
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    Dir.mkdir util_inst_bindir
    File.chmod 0000, util_inst_bindir

    assert_raises Gem::FilePermissionError do
      @installer.generate_bin @spec, @gemhome
    end

  ensure
    File.chmod 0700, util_inst_bindir unless $DEBUG
  end

  def test_generate_bin_symlinks_update_newer
    return if win_platform? #Windows FS do not support symlinks
    
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec '0.0.3'
    @installer.directory = File.join util_gem_dir('0.0.3')
    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_bindir('0.0.3'), "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlinks_update_older
    return if win_platform? #Windows FS do not support symlinks

    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir, "bin", "my_exec"),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.1"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec '0.0.1'
    @installer.directory = util_gem_dir('0.0.1')
    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir('0.0.2'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink not moved")
  end

  def test_generate_bin_symlinks_update_remove_wrapper
    return if win_platform? #Windows FS do not support symlinks

    @installer.options[:wrappers] = true
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exists?(installed_exec)

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "0.0.3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    @installer.options[:wrappers] = false
    util_make_exec '0.0.3'
    @installer.directory = util_gem_dir '0.0.3'
    @installer.generate_bin @spec, @gemhome
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal(File.join(util_gem_dir('0.0.3'), "bin", "my_exec"),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generated_bin_uses_default_shebang
    return if win_platform? #Windows FS do not support symlinks

    @installer.options[:wrappers] = true
    util_make_exec
    @installer.directory = util_gem_dir

    @installer.generate_bin @spec, @gemhome 

    default_shebang = File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name'])
    shebang_line = open("#{@gemhome}/bin/my_exec") { |f| f.readlines.first }
    assert_match(/\A#!/, shebang_line)
    assert_match(/#{default_shebang}/, shebang_line)
  end

  def test_generate_bin_symlinks_win32
    old_arch = Config::CONFIG["arch"]
    Config::CONFIG["arch"] = "win32"
    @installer.options[:wrappers] = false
    util_make_exec
    @installer.directory = util_gem_dir

    use_ui @ui do
      @installer.generate_bin @spec, @gemhome
    end

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, "my_exec")
    assert_equal true, File.exist?(installed_exec)

    assert_match(/Unable to use symlinks on win32, installing wrapper/i,
                 @ui.error)
    
    expected_mode = win_platform? ? 0100644 : 0100755
    assert_equal expected_mode, File.stat(installed_exec).mode

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  ensure
    Config::CONFIG["arch"] = old_arch
  end

  def test_install
    gem = nil
    @spec.files = %w[lib/code.rb]
    @spec.executables = 'executable'

    Dir.chdir @tempdir do
      Dir.mkdir 'bin'
      Dir.mkdir 'lib'
      File.open File.join('bin', 'executable'), 'w' do |f| f.puts '1' end
      File.open File.join('lib', 'code.rb'), 'w' do |f| f.puts '1' end

      use_ui @ui do
        Gem::Builder.new(@spec).build
        gem = File.join @tempdir, "#{@spec.full_name}.gem"
      end
    end

    assert_equal @spec, @installer.install

    gemdir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist?(gemdir)

    exe = File.join(gemdir, 'bin', 'executable')
    assert File.exist?(exe)
    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode
    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist?(File.join(@gemhome, 'specifications',
                                 "#{@spec.full_name}.gemspec"))
  end

  def test_install_bad_gem
    gem = nil
    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end
      gem = File.join @tempdir, "#{@spec.full_name}.gem"
    end

    gem_data = File.open gem, 'rb' do |fp| fp.read 1024 end
    File.open gem, 'wb' do |fp| fp.write gem_data end

    e = assert_raise Gem::InstallError do
      @installer.install
    end

    assert_equal "invalid gem format for #{gem}", e.message
  end

  def test_install_force
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required
      installer.install true
    end

    gem_dir = File.join(@gemhome, 'gems', 'old_ruby_required-0.0.1')
    assert File.exist?(gem_dir)
  end

  def test_install_missing_dirs
    FileUtils.rm_f File.join(Gem.dir, 'cache')
    FileUtils.rm_f File.join(Gem.dir, 'docs')
    FileUtils.rm_f File.join(Gem.dir, 'specifications')

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end
      gem = File.join @tempdir, "#{@spec.full_name}.gem"

      @installer.install
    end

    File.directory? File.join(Gem.dir, 'cache')
    File.directory? File.join(Gem.dir, 'docs')
    File.directory? File.join(Gem.dir, 'specifications')
  end

  def test_install_with_message
    @spec.post_install_message = 'I am a shiny gem!'

    use_ui @ui do
      Dir.chdir @tempdir do Gem::Builder.new(@spec).build end

      @installer.install
    end

    assert_match %r|I am a shiny gem!|, @ui.output
  end

  def test_install_wrong_ruby_version
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required
      e = assert_raise Gem::InstallError do
        installer.install
      end
      assert_equal 'old_ruby_required requires Ruby version = 1.4.6',
                   e.message
    end
  end

  def test_install_wrong_rubygems_version
    spec = quick_gem 'old_rubygems_required', '0.0.1' do |s|
      s.required_rubygems_version = '< 0.0.0'
    end

    util_build_gem spec

    gem = File.join @gemhome, 'cache', "#{spec.full_name}.gem"

    use_ui @ui do
      @installer = Gem::Installer.new gem
      e = assert_raise Gem::InstallError do
        @installer.install
      end
      assert_equal 'old_rubygems_required requires RubyGems version < 0.0.0',
                   e.message
    end
  end

  def old_ruby_required
    spec = quick_gem 'old_ruby_required', '0.0.1' do |s|
      s.required_ruby_version = '= 1.4.6'
    end

    util_build_gem spec

    File.join @gemhome, 'cache', "#{spec.full_name}.gem"
  end

end

