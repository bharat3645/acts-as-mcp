require_relative "test_helper"

# Regression test for the "real, unedited output" claim in README.md's
# "Example: the real wire protocol" section - cycle 98 found that block had
# drifted (stale "0.1.0" version string, and the script now also emits a
# tools/list call and an unregistered-tool call the README excerpt no
# longer showed) because nothing re-derived it from the real script after
# VERSION was bumped. Running the real example and diffing its full output
# against the documented block means this can't drift silently again.
class ReadmeConsistencyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_plain_tools_example_output_matches_the_readme_exactly
    real_output = IO.popen(
      ["ruby", "-I", File.join(ROOT, "lib"), File.join(ROOT, "examples", "plain_tools.rb")],
      chdir: ROOT, external_encoding: Encoding::UTF_8, &:read
    )

    readme = File.read(File.join(ROOT, "README.md"), encoding: Encoding::UTF_8)
    heading = "## Example: the real wire protocol"
    idx = readme.index(heading)
    refute_nil idx, "README is missing the '#{heading}' section"

    fenced = readme[idx..].match(/```\n(.*?)```/m)
    refute_nil fenced, "could not find the fenced code block documenting plain_tools.rb's output"

    assert_equal real_output.strip, fenced[1].strip,
      "README's plain_tools.rb output block has drifted from the real script output - " \
      "re-run `ruby -Ilib examples/plain_tools.rb` and paste the real output"
  end
 end
