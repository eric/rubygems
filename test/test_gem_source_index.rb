#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/source_index'
require 'rubygems/config_file'

class Gem::SourceIndex
  public :fetcher, :fetch_bulk_index, :fetch_quick_index,
         :find_missing, :gems, :remove_extra,
         :update_with_missing, :unzip
end

class TestGemSourceIndex < RubyGemTestCase

  def setup
    super

    util_setup_fake_fetcher
  end

  def test_create_from_directory
    # TODO
  end

  def test_fetcher
    assert_equal @fetcher, @source_index.fetcher
  end

  def test_fetch_bulk_index_compressed
    util_setup_bulk_fetch true

    use_ui @ui do
      fetched_index = @source_index.fetch_bulk_index @uri
      assert_equal [@a1.full_name, @a2.full_name, @a_evil9.full_name,
                    @c1_2.full_name].sort,
                   fetched_index.gems.map { |n,s| n }.sort
    end

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}.Z", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_fetch_bulk_index_error
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}.Z"] = proc { raise SocketError }
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = proc { raise SocketError }
    @fetcher.data["#{@gem_repo}/yaml.Z"] = proc { raise SocketError }
    @fetcher.data["#{@gem_repo}/yaml"] = proc { raise SocketError }

    e = assert_raise Gem::RemoteSourceException do
      use_ui @ui do
        @source_index.fetch_bulk_index @uri
      end
    end

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}.Z", paths.shift
    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}", paths.shift
    assert_equal "#{@gem_repo}/yaml.Z", paths.shift
    assert_equal "#{@gem_repo}/yaml", paths.shift

    assert paths.empty?, paths.join(', ')

    assert_equal 'Error fetching remote gem cache: SocketError',
                 e.message
  end

  def test_fetch_bulk_index_fallback
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}.Z"] =
      proc { raise SocketError }
    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] =
      proc { raise SocketError }
    @fetcher.data["#{@gem_repo}/yaml.Z"] = proc { raise SocketError }
    @fetcher.data["#{@gem_repo}/yaml"] = @source_index.to_yaml

    use_ui @ui do
      fetched_index = @source_index.fetch_bulk_index @uri
      assert_equal [@a1.full_name, @a2.full_name, @a_evil9.full_name,
                    @c1_2.full_name].sort,
                   fetched_index.gems.map { |n,s| n }.sort
    end

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}.Z", paths.shift
    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}", paths.shift
    assert_equal "#{@gem_repo}/yaml.Z", paths.shift
    assert_equal "#{@gem_repo}/yaml", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_fetch_bulk_index_marshal_mismatch
    marshal = @source_index.dump
    marshal[0] = (Marshal::MAJOR_VERSION - 1).chr

    @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = marshal
    @fetcher.data["#{@gem_repo}/yaml"] = @source_index.to_yaml

    use_ui @ui do
      fetched_index = @source_index.fetch_bulk_index @uri
      assert_equal [@a1.full_name, @a2.full_name, @a_evil9.full_name,
                    @c1_2.full_name].sort,
                   fetched_index.gems.map { |n,s| n }.sort
    end

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}.Z", paths.shift
    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}", paths.shift
    assert_equal "#{@gem_repo}/yaml.Z", paths.shift
    assert_equal "#{@gem_repo}/yaml", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_fetch_bulk_index_uncompressed
    util_setup_bulk_fetch false
    use_ui @ui do
      fetched_index = @source_index.fetch_bulk_index @uri
      assert_equal [@a1.full_name, @a2.full_name, @a_evil9.full_name,
                    @c1_2.full_name].sort,
                   fetched_index.gems.map { |n,s| n }.sort
    end

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}.Z", paths.shift
    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_fetch_quick_index
    quick_index = util_zip @gem_names
    @fetcher.data["#{@gem_repo}/quick/index.rz"] = quick_index

    quick_index = @source_index.fetch_quick_index @uri
    assert_equal [@a1.full_name, @a2.full_name, @b2.full_name].sort,
                 quick_index.sort

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/quick/index.rz", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_fetch_quick_index_error
    @fetcher.data["#{@gem_repo}/quick/index.rz"] =
      proc { raise Exception }

    e = assert_raise Gem::OperationNotSupportedError do
      @source_index.fetch_quick_index @uri
    end

    assert_equal 'No quick index found: Exception', e.message

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/quick/index.rz", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_find_missing
    missing = @source_index.find_missing [@b2.full_name]
    assert_equal [@b2.full_name], missing
  end

  def test_find_missing_none_missing
    missing = @source_index.find_missing [
      @a1.full_name, @a2.full_name, @c1_2.full_name
    ]

    assert_equal [], missing
  end

  def test_latest_specs
    p1_ruby = quick_gem 'p', '1'
    p1_platform = quick_gem 'p', '1' do |spec|
      spec.platform = Gem::Platform::CURRENT
    end

    a1_platform = quick_gem @a1.name, (@a1.version) do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    a2_platform = quick_gem @a2.name, (@a2.version) do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end

    a2_platform_other = quick_gem @a2.name, (@a2.version) do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    a3_platform_other = quick_gem @a2.name, (@a2.version.bump) do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    @source_index.add_spec p1_ruby
    @source_index.add_spec p1_platform
    @source_index.add_spec a1_platform
    @source_index.add_spec a2_platform
    @source_index.add_spec a2_platform_other
    @source_index.add_spec a3_platform_other

    expected = [
      @a2.full_name,
      a2_platform.full_name,
      a3_platform_other.full_name,
      @c1_2.full_name,
      @a_evil9.full_name,
      p1_ruby.full_name,
      p1_platform.full_name,
    ].sort

    latest_specs = @source_index.latest_specs.map { |s| s.full_name }.sort

    assert_equal expected, latest_specs
  end

  def test_load_gems_in
    spec_dir1 = File.join @gemhome, 'specifications'
    spec_dir2 = File.join @tempdir, 'gemhome2', 'specifications'

    FileUtils.rm_r spec_dir1

    FileUtils.mkdir_p spec_dir1
    FileUtils.mkdir_p spec_dir2

    a1 = quick_gem 'a', '1' do |spec| spec.author = 'author 1' end
    a2 = quick_gem 'a', '1' do |spec| spec.author = 'author 2' end

    File.open File.join(spec_dir1, "#{a1.full_name}.gemspec"), 'w' do |fp|
      fp.write a1.to_ruby
    end

    File.open File.join(spec_dir2, "#{a2.full_name}.gemspec"), 'w' do |fp|
      fp.write a2.to_ruby
    end

    @source_index.load_gems_in spec_dir1, spec_dir2

    assert_equal a1.author, @source_index.specification(a1.full_name).author
  end

  def test_outdated
    util_setup_source_info_cache

    assert_equal [], @source_index.outdated

    updated = quick_gem @a2.name, (@a2.version.bump)
    util_setup_source_info_cache updated

    assert_equal [updated.name], @source_index.outdated

    updated_platform = quick_gem @a2.name, (updated.version.bump) do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    util_setup_source_info_cache updated, updated_platform

    assert_equal [updated_platform.name], @source_index.outdated
  end

  def test_remove_extra
    @source_index.add_spec @a1
    @source_index.add_spec @a2

    @source_index.remove_extra [@a1.full_name]

    assert_equal [@a1.full_name], @source_index.gems.map { |n,s| n }
  end

  def test_remove_extra_no_changes
    gems = [@a1.full_name, @a2.full_name]
    @source_index.add_spec @a1
    @source_index.add_spec @a2

    @source_index.remove_extra gems

    assert_equal gems, @source_index.gems.map { |n,s| n }.sort
  end

  def test_search
    assert_equal [@a1, @a2, @a_evil9], @source_index.search('a')
    assert_equal [@a2], @source_index.search('a', '= 2')

    assert_equal [], @source_index.search('bogusstring')
    assert_equal [], @source_index.search('a', '= 3')

    source_index = Gem::SourceIndex.new
    source_index.add_spec @a1
    source_index.add_spec @a2

    assert_equal [@a1], source_index.search(@a1.name, '= 1')

    r1 = Gem::Requirement.create '= 1'
    assert_equal [@a1], source_index.search(@a1.name, r1)

    dep = Gem::Dependency.new @a1.name, r1
    assert_equal [@a1], source_index.search(dep)
  end

  def test_search_empty_cache
    empty_source_index = Gem::SourceIndex.new({})
    assert_equal [], empty_source_index.search("foo")
  end

  def test_search_platform
    util_set_arch 'x86-my_platform1'

    a1 = quick_gem 'a', '1'
    a1_mine = quick_gem 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-my_platform1'
    end
    a1_other = quick_gem 'a', '1' do |s|
      s.platform = Gem::Platform.new 'x86-other_platform1'
    end

    si = Gem::SourceIndex.new(a1.full_name => a1, a1_mine.full_name => a1_mine,
                              a1_other.full_name => a1_other)

    dep = Gem::Dependency.new 'a', Gem::Requirement.new('1')

    gems = si.search dep, true

    assert_equal [a1, a1_mine], gems.sort
  end

  def test_signature
    sig = @source_index.gem_signature('foo-1.2.3')
    assert_equal 64, sig.length
    assert_match(/^[a-f0-9]{64}$/, sig)
  end

  def test_specification
    assert_equal @a1, @source_index.specification(@a1.full_name)

    assert_nil @source_index.specification("foo-1.2.4")
  end

  def test_index_signature
    sig = @source_index.index_signature
    assert_match(/^[a-f0-9]{64}$/, sig)
  end

  def test_unzip
    input = "x\234+\316\317MU(I\255(\001\000\021\350\003\232"
    assert_equal 'some text', @source_index.unzip(input)
  end

  def test_update_bulk
    util_setup_bulk_fetch true

    @source_index.gems.replace({})
    assert_equal [], @source_index.gems.keys.sort

    use_ui @ui do
      @source_index.update @uri

      assert_equal [@a1.full_name, @a2.full_name, @a_evil9.full_name,
                    @c1_2.full_name],
                   @source_index.gems.keys.sort
    end

    paths = @fetcher.paths

    assert_equal "#{@gem_repo}/quick/index.rz", paths.shift
    assert_equal "#{@gem_repo}/Marshal.#{@marshal_version}.Z", paths.shift

    assert paths.empty?, paths.join(', ')
  end

  def test_update_incremental
    old_gem_conf = Gem.configuration
    Gem.configuration = Gem::ConfigFile.new([])

    quick_index = util_zip @all_gem_names.join("\n")
    @fetcher.data["#{@gem_repo}/quick/index.rz"] = quick_index

    marshal_uri = File.join @gem_repo, "quick", "Marshal.#{@marshal_version}",
                            "#{@b2.full_name}.gemspec.rz"
    @fetcher.data[marshal_uri] = util_zip Marshal.dump(@b2)

    use_ui @ui do
      @source_index.update @uri

      assert_equal @all_gem_names, @source_index.gems.keys.sort
    end

    paths = @fetcher.paths
    assert_equal "#{@gem_repo}/quick/index.rz", paths.shift
    assert_equal marshal_uri, paths.shift

    assert paths.empty?, paths.join(', ')
  ensure
    Gem.configuration = old_gem_conf
  end

  def test_update_incremental_fallback
    old_gem_conf = Gem.configuration
    Gem.configuration = Gem::ConfigFile.new([])

    quick_index = util_zip @all_gem_names.join("\n")
    @fetcher.data["#{@gem_repo}/quick/index.rz"] = quick_index

    marshal_uri = File.join @gem_repo, "quick", "Marshal.#{@marshal_version}",
                            "#{@b2.full_name}.gemspec.rz"

    yaml_uri = "#{@gem_repo}/quick/#{@b2.full_name}.gemspec.rz"
    @fetcher.data[yaml_uri] = util_zip @b2.to_yaml

    use_ui @ui do
      @source_index.update @uri

      assert_equal @all_gem_names, @source_index.gems.keys.sort
    end

    paths = @fetcher.paths
    assert_equal "#{@gem_repo}/quick/index.rz", paths.shift
    assert_equal marshal_uri, paths.shift
    assert_equal yaml_uri, paths.shift

    assert paths.empty?, paths.join(', ')
  ensure
    Gem.configuration = old_gem_conf
  end

  def test_update_incremental_marshal_mismatch
    old_gem_conf = Gem.configuration
    Gem.configuration = Gem::ConfigFile.new([])

    quick_index = util_zip @all_gem_names.join("\n")
    @fetcher.data["#{@gem_repo}/quick/index.rz"] = quick_index

    marshal_uri = File.join @gem_repo, "quick", "Marshal.#{@marshal_version}",
                            "#{@b2.full_name}.gemspec.rz"
    marshal_data = Marshal.dump(@b2)
    marshal_data[0] = (Marshal::MAJOR_VERSION - 1).chr
    @fetcher.data[marshal_uri] = util_zip marshal_data

    yaml_uri = "#{@gem_repo}/quick/#{@b2.full_name}.gemspec.rz"
    @fetcher.data[yaml_uri] = util_zip @b2.to_yaml

    use_ui @ui do
      @source_index.update @uri

      assert_equal @all_gem_names, @source_index.gems.keys.sort
    end

    paths = @fetcher.paths
    assert_equal "#{@gem_repo}/quick/index.rz", paths.shift
    assert_equal marshal_uri, paths.shift
    assert_equal yaml_uri, paths.shift

    assert paths.empty?, paths.join(', ')
  ensure
    Gem.configuration = old_gem_conf
  end

  def test_update_with_missing
    marshal_uri = File.join @gem_repo, "quick", "Marshal.#{@marshal_version}",
                            "#{@c1_2.full_name}.gemspec.rz"
    dumped = Marshal.dump @c1_2
    @fetcher.data[marshal_uri] = util_zip(dumped)

    use_ui @ui do
      @source_index.update_with_missing @uri, [@c1_2.full_name]
    end

    spec = @source_index.specification(@c1_2.full_name)
    # We don't care about the equality of undumped attributes
    @c1_2.files = spec.files
    @c1_2.loaded_from = spec.loaded_from

    assert_equal @c1_2, spec
  end

  def util_setup_bulk_fetch(compressed)
    source_index = @source_index.dump

    if compressed then
      @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}.Z"] = util_zip source_index
    else
      @fetcher.data["#{@gem_repo}/Marshal.#{@marshal_version}"] = source_index
    end
  end

end

