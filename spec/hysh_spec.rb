# -*- ruby-indent-level: 2; -*-

require_relative "../lib/hysh.rb"

describe Hysh do
  describe ".run" do
    it "run command and return whether exit with 0" do
      expect(Hysh.run('true')).to eql(true)
      expect(Hysh.run('false')).to eql(false)
    end

    it "call ruby function" do
      expect(Hysh.run { true }).to eql(true)
      expect(Hysh.run { false }).to eql(false)
    end
  end

  describe ".out_s" do
    it "run command and return its output" do
      expect(Hysh.out_s("echo", "-n", "abc")).to eql(["abc", true])
    end

    it "run ruby function in process and return its output" do
      expect(Hysh.out_s ->{ $stdout.write "abc" }).to eql(["abc", 3])
    end
  end

  describe ".io_s" do
    it "run command, given input and return its output" do
      expect(Hysh.io_s("abc", "tr", "ab", "AB")).to eql(["ABc", true])
    end
  end

  describe ".pipe" do
    it "run commands in pipe line" do
      expect(Hysh.out_s ->{ Hysh.pipe(["echo", "-n", "abc"], ["tr", "ab", "AB"]) }).to eql(["ABc", true])
    end
  end
end

class TestScript
  def test
    @x = 4
    hysh_script {
      pipe ['echo', '1', '2'], ['wc', '-w']
    }
  end
end

def test_script
  t = TestScript.new
  class << t
    def method_missing(m, *args)
      raise NoMethodError
    end
  end
  t
end

describe "hysh_script" do
  it "run Hysh methods directly" do
    expect(hysh_script { out_ss { run "echo", "12" } }).to eql(["12", true])
  end
  it "run commands as function" do
    expect(hysh_script { out_ss { echo 12 } }).to eql(["12", true])
    expect(Hysh.out_ss { test_script.test }).to eql(["2", true])
  end
end
