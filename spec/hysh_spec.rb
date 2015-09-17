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
