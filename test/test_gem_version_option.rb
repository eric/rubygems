require 'test/unit'
require 'test/gemutilities'
require 'rubygems/command'
require 'rubygems/version_option'

class TestGemVersionOption < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Command.new 'dummy', 'dummy'
    @cmd.extend Gem::VersionOption
  end

  def test_add_platform_option
    @cmd.add_platform_option

    assert @cmd.handles?(%w[--platform x86-darwin])
  end

  def test_add_version_option
    @cmd.add_version_option

    assert @cmd.handles?(%w[--version >1])
  end

  def test_platform_option
    @cmd.add_platform_option

    @cmd.handle_options %w[--platform x86-darwin]

    expected = { :platform => Gem::Platform.new('x86-darwin'), :args => [] }

    assert_equal expected, @cmd.options
  end

  def test_version_option
    @cmd.add_version_option

    @cmd.handle_options %w[--version >1]

    expected = { :version => Gem::Requirement.new('> 1'), :args => [] }

    assert_equal expected, @cmd.options
  end

end

