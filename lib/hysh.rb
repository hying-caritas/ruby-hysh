# -*- ruby-indent-level: 2; -*-
#
# Hysh: Huang Ying's Shell in Ruby
#
# Copyright (c) 2015 Huang Ying <huang.ying.caritas@gmail.com>
#
# LGPL v2.0 or later.

require 'tempfile'

# Hysh stands for Huang Ying's Shell in Ruby.  Like other shells, it
# can redirect IO, run external programs, and glue processes (like
# pipeline), etc.  One of the best stuff it can do is to write
# pipeline filter in Ruby.
#
module Hysh
  # :stopdoc:
  TEMP_BASE = "hysh-"
  @@redirections = []
  IGNORE = :ignore
  WARN = :warn
  RAISE = :raise
  @@on_command_error = IGNORE
  # :startdoc:

  # :section: Common Utilities

  # :call-seq:
  #   with_set_globals(var_name, val, ...) { ... }
  #
  # Set the global variable named +var_name+ (a string or symbol) to
  # +val+, then run the block, return the return value of the block.
  # Restore the original value of the variable upon returning.
  # Multiple pairs of +var_name+ and +val+ can be specified.
  def self.with_set_globals(*var_vals)
    orig_var_vals = var_vals.each_slice(2).map { |var, val|
      svar = var.to_s
      unless svar.start_with? '$'
	raise ArgumentError, "Invalid global variable name: #{svar}"
      end
      orig_val = eval(svar)
      [svar, val, orig_val]
    }
    orig_var_vals.each { |var, val|
      eval("#{var} = val")
    }
    yield
  ensure
    if orig_var_vals
      orig_var_vals.each { |var, val, orig_val|
	eval("#{var} = orig_val")
      }
    end
  end

  # :section: IO Redirection

  # :call-seq:
  #   with_redirect_to(fd, var_name, io) { ... }
  #
  # Set the variable named +var_name+ (usually +$stdin+, +$stdout+,
  # +$stderr, etc.) to +io+ (redirection in Ruby), and arrange to
  # redirect the +fd+ (usally 0, 1, 2, etc. to +io+ for the external
  # programs, then run the block, return the return value of the
  # block.  Restore the original value of the variable and cancel the
  # arrangement to external program redirections upon returning.
  def self.with_redirect_to(fd, var, io, &b)
    @@redirections.push([fd, io]) if fd
    if var
      with_set_globals(var, io, &b)
    else
      yield
    end
  ensure
    @@redirections.pop if fd
  end

  # :call-seq:
  #   with_redirect_stdin_to(io) { ... }
  #
  # Set the +$stdin+ to +io+ (redirection in Ruby), and arrange to
  # redirect the file descriptor 0 to +io+ for the external programs,
  # then run the block, return the return value of the block.  Restore
  # the original value of the $stdin and cancel the arrangement to
  # external program redirections upon returning.
  def self.with_redirect_stdin_to(io, &b)
    with_redirect_to(0, :$stdin, io, &b)
  end

  # :call-seq:
  #   with_redirect_stdout_to(io) { ... }
  #
  # Set the +$stdout+ to +io+ (redirection in Ruby), and arrange to
  # redirect the file descriptor 1 to +io+ for the external programs,
  # then run the block, return the return value of the block.  Restore
  # the original value of the $stdout and cancel the arrangement to
  # external program redirections upon returning.
  def self.with_redirect_stdout_to(io, &b)
    with_redirect_to(1, :$stdout, io, &b)
  end

  # :call-seq:
  #   with_redirect_stderr_to(io) { ... }
  #
  # Set the +$stderr+ to +io+ (redirection in Ruby), and arrange to
  # redirect the file descriptor 2 to +io+ for the external programs,
  # then run the block, return the return value of the block.  Restore
  # the original value of the $stderr and cancel the arrangement to
  # external program redirections upon returning.
  def self.with_redirect_stderr_to(io, &b)
    with_redirect_to(2, :$stderr, io, &b)
  end

  # :call-seq:
  #   with_redirect_stdin_file(args...) { ... }
  #
  # Open the file with parameters: +args+, which are same as the
  # parameters of +File.open+.  Set the +$stdin+ to the return +io+
  # (redirection in Ruby), and arrange to redirect the file descriptor
  # 0 to the returned +io+ for the external programs, then run the
  # block, return the return value of the block.  Restore the original
  # value of the $stdin and cancel the arrangement to external program
  # redirections upon returning.
  def self.with_redirect_stdin_to_file(*args, &b)
    File.open(*args) { |f|
      with_redirect_stdin_to f, &b
    }
  end

  # :call-seq:
  #   with_redirect_stdout_file(args...) { ... }
  #
  # Open the file with parameters: +args+, which are same as the
  # parameters of +File.open+.  Set the +$stdout+ to the return +io+
  # (redirection in Ruby), and arrange to redirect the file descriptor
  # 1 to the returned +io+ for the external programs, then run the
  # block, return the return value of the block.  Restore the original
  # value of the $stdout and cancel the arrangement to external
  # program redirections upon returning.
  def self.with_redirect_stdout_to_file(*args, &b)
    if args.size == 1
      args.push "w"
    end
    File.open(*args) { |f|
      with_redirect_stdout_to f, &b
    }
  end

  # :call-seq:
  #   with_redirect_stderr_file(args...) { ... }
  #
  # Open the file with parameters: +args+, which are same as the
  # parameters of +File.open+.  Set the +$stderr+ to the return +io+
  # (redirection in Ruby), and arrange to redirect the file descriptor
  # 2 to the returned +io+ for the external programs, then run the
  # block, return the return value of the block.  Restore the original
  # value of the $stderr and cancel the arrangement to external
  # program redirections upon returning.
  def self.with_redirect_stderr_to_file(*args, &b)
    if args.size == 1
      args.push "w"
    end
    File.open(*args) { |f|
      with_redirect_stderr_to f, &b
    }
  end

  def self.__out_io(args, options, proc_arg) # :nodoc:
    Tempfile.open(TEMP_BASE) { |tempf|
      tempf.unlink
      ret = nil
      with_redirect_stdout_to(tempf) {
	ret = __run args, options, proc_arg
      }
      tempf.rewind
      stuff = yield tempf
      [stuff, ret]
    }
  end

  # :call-seq:
  #   out_s() { ... } -> [string, any]
  #   out_s(function) -> [string, any]
  #   out_s(command...[, options]) -> [string, true or false]
  #
  # Collect the output of running the block, or the function specified
  # via +function+ or the external program specified via +command+ and
  # +options+ via stdout redirection. +command+ and +options+
  # parameters are same as that of +Process.spawn+.  Return the
  # collected output string and the return value of the block or the
  # function or exit success status of the external program as a two
  # element array.  Restore stdout redirection upon returning.
  def self.out_s(*args, &blk)
    __out_io(*__parse_args(args, blk)) { |tempf|
      tempf.read
    }
  end

  # :call-seq:
  #   out_ss() { ... } -> [string, any]
  #   out_ss(function) -> [string, any]
  #   out_ss(command...[, options]) -> [string, true or false]
  #
  # Same as out_s, except the collected output string are right
  # stripped before return.
  def self.out_ss(*args_in, &blk)
    s, ret = out_s(*args_in, &blk)
    [s.rstrip, ret]
  end

  # :call-seq:
  #   out_lines(funciton) -> [array of string, any]
  #   out_lines(command...[, options]) -> [array of string, any]
  #   out_lines(function) { |line| ... } -> true or false
  #   out_lines(command...[, options]) { |line| ... } -> true or false
  #
  # If no block is supplied, collect the output of running the
  # function specified via +function+ or the external program specified
  # via +command+ and +options+ via stdout redirection.  +command+ and
  # +options+ are same as that of +Process.spawn+.  Return the
  # collected string as lines and the return value of the block or the
  # function or exit success status of the external program.  Restore
  # stdout redirection upon returning.
  #
  # If block is supplied, collect the output of running the function
  # specified via +function+ (in a forked sub-process) or the external
  # program specified via +command+ and +options+ via stdout
  # redirection.  +command+ and +options+ are same as that of
  # +Process.spawn+.  Feed each line of output to the block as +line+.
  # Return the exit success status of the forked sub-process or the
  # external program.  Restore stdout redirection upon returning.
  def self.out_lines(*args_in, &blk)
    args, options, proc_arg = __parse_args args_in
    if block_given?
      __popen(nil, true, nil, args, options, proc_arg) { |pid, stdin, stdout, stderr|
	stdout.each_line(&blk)
	Process.waitpid pid
	__check_command_status args_in
      }
    else
      __out_io(args, options, proc_arg) { |tempf|
	tempf.readlines
      }
    end
  end

  # :call-seq:
  #   out_err_s() { ... } -> [string, any]
  #   out_err_s(function) -> [string, any]
  #   out_err_s(command...[, options]) -> [string, true or false]
  #
  # Same as out_s, except collect output of stderr too.
  def self.out_err_s(*args_in, &blk)
    args, options, proc_arg = __parse_args args_in, blk
    Tempfile.open(TEMP_BASE) { |tempf|
      tempf.unlink
      ret = nil
      with_redirect_stdout_to(tempf) {
	with_redirect_stderr_to(tempf) {
	  ret = __run args, options, proc_arg
	}
      }
      tempf.rewind
      s = tempf.read
      [s, ret]
    }
  end

  # :call-seq:
  #   out_err_ss() { ... } -> [string, any]
  #   out_err_ss(function) -> [string, any]
  #   out_err_ss(command...[, options]) -> [string, true or false]
  #
  # Same as out_err_s, except the collected output string are right
  # stripped before return.
  def self.out_err_ss(*args_in, &blk)
    s, ret = out_err_s(*args_in, &blk)
    [s.rstrip. ret]
  end

  def self.__in_io(args, options, proc_arg) # :nodoc:
    Tempfile.open(TEMP_BASE) { |tempf|
      tempf.unlink
      yield tempf
      tempf.rewind
      with_redirect_stdin_to(tempf) {
	__run args, options, proc_arg
      }
    }
  end

  # :call-seq:
  #   in_s(string) { ... } -> any
  #   in_s(string, function) -> any
  #   in_s(string, command...[, options]) -> true or false
  #
  # Feed the string specified via +string+ to the running of the
  # block, or the function specified via +function+ or the external
  # program specified via +command+ and +options+ via stdin
  # redirection. +command+ and +options+ are same as that of
  # +Process.spawn+.  Return the return value of the block or the
  # function or the exit success status of the external program.
  # Restore stdin redirection upon returning.
  def self.in_s(s, *args_in, &blk)
    args, options, proc_arg = __parse_args args_in, blk
    __in_io(args, options, proc_arg) { |tempf|
      tempf.write s
    }
  end

  # :call-seq:
  #   in_lines(lines) { ... } -> any
  #   in_lines(lines, function) -> any
  #   in_lines(lines, command...[, options]) -> true or false
  #
  # Same as +in_s+, except input string are specified via +lines+
  # (Array of String).
  def self.in_lines(lines, *args_in, &blk)
    args, options, proc_arg = __parse_args args_in, blk
    __in_io(args, options, proc_arg) { |tempf|
      lines.each { |line| tempf.write line }
    }
  end

  # :call-seq:
  #   io_s(string) { ... } -> [string, any]
  #   io_s(string, function) -> [string, any]
  #   io_s(stirng, command...[, options]) -> [string, true or false]
  #
  # Redirect the stdin and stdout like that of +in_s+ and +out_s+,
  # return value is same of +out_s+.
  def self.io_s(s, *args_in, &blk)
    in_s(s) {
      out_s {
	run *args_in, &blk
      }
    }
  end

  # :call-seq:
  #   io_ss(string) { ... } -> [string, any]
  #   io_ss(string, function) -> [string, any]
  #   io_ss(stirng, command...[, options]) -> [string, true or false]
  #
  # Same as +io_s+, except the output string is right stripped before
  # returning.
  def self.io_ss(s, *args_in, &blk)
    s = io_s(s, *args_in, &blk)
    s.rstrip
  end

  # :section: Run Process

  # :call-seq:
  #   ignore_on_command_error() { ... }
  #
  # When running the block, the non-zero exit status of running
  # external program are ignored.  The original behavior is restored
  # upon returning.
  def self.ignore_on_command_error(&b)
    with_set_globals(:@@on_command_error, IGNORE, &b)
  end

  # :call-seq:
  #   warn_on_command_error() { ... }
  #
  # When running the block, the warning message will be print to
  # $stderr when the external program exited with non-zero status.
  # The original behavior is restored upon returning.
  def self.warn_on_command_error(&b)
    with_set_globals(:@@on_command_error, WARN, &b)
  end

  # :call-seq:
  #   raise_on_command_error() { ... }
  #
  # When running the block, an +Hysh::CommandError+ exception will be
  # raised when the external program exited with non-zero status.  The
  # original behavior is restored upon returning.
  def self.raise_on_command_error(&b)
    with_set_globals(:@@on_command_error, RAISE, &b)
  end

  def self.__parse_args(args, blk = nil) # :nodoc:
    args = [args] unless args.is_a? Array
    if args.last.is_a?(Hash)
      options = args.pop
    else
      options = {}
    end
    if args.empty?
      if blk.equal? nil
	raise ArgumentError.new('No argument or block!')
      else
	args = [blk]
	proc_arg = true
      end
    else
      proc_arg = args.size == 1 && args.first.is_a?(Proc)
    end
    [args, options, proc_arg]
  end

  # :call-seq:
  #   with_change_env(env_var, val, ...) { ... }
  #
  # When running the block, the environment will be changed as
  # specified via parameters.  The +env_var+ specifies the environment
  # variable name, and the +val+ specifies the value, when +val+ is
  # nil, the envioronment variable will be removed.  Multiple pairs of
  # the environment variable names and values can be specified.  The
  # changes to the environment are restored upon returning.
  def self.with_change_env(*var_vals)
    orig_var_vals = var_vals.each_slice(2).map { |var, val|
      orig_val = ENV[var]
      [var, orig_val]
    }
    var_vals.each_slice(2) { |var, val|
      ENV[var] = val
    }
    yield
  ensure
    if orig_var_vals
      orig_var_vals.each { |var, orig_val|
	ENV[var] = orig_val
      }
    end
  end

  # :call-seq:
  #   chdir(dir) { ... }
  #
  # Same as +Dir.chdir+.
  def self.chdir(dir, &b)
    Dir.chdir(dir, &b)
  end

  def self.__spawn(args, options_in, proc_arg) # :nodoc:
    if proc_arg
      Process.fork {
	fclose = options_in[:close] || []
	fclose.each { |f| f.close }
	fin = options_in[0]
	fout = options_in[1]
	fd_in, var_in = fin ? [0, :$stdin] : [nil, nil]
	fd_out, var_out = fout ? [1, :$stdout] : [nil, nil]
	with_redirect_to(fd_in, var_in, fin) {
	  with_redirect_to(fd_out, var_out, fout) {
	    begin
	      exit 1 unless args.first.()
	    rescue => e
	      $stderr.puts e
	      $stderr.puts e.backtrace
	      exit 1
	    end
	  }
	}
      }
    else
      options = Hash[@@redirections]
      options[:close_others] = true
      options.merge! options_in
      Process.spawn(*args, options)
    end
  end

  # :call-seq:
  #   spawn() { ... } -> pid
  #   spawn(function) -> pid
  #   spawn(command...[, options]) -> pid
  #
  # Run the block or the function specified via +function+ in a forked
  # sub-process, or run external program specified via +command+ and
  # +options+, +command+ and +options+ are same as that of
  # Process.spawn.  Return the +pid+.
  def self.spawn(*args_in, &blk)
    __spawn *__parse_args(args_in, blk)
  end

  # Exception class raised when an external program exits with
  # non-zero status and raise_on_command_error take effect.
  class CommandError < StandardError
    # :call-seq:
    #   CommandError.new(cmdline, status)
    #
    # Create an instance of CommandError class, for the external
    # program command line specified via +cmdline+ as an array of
    # string and failed exit status specified via +status+ as
    # Process::Status.
    def initialize(cmdline, status)
      @cmdline = cmdline
      @status = status
      reason = if status.exited?
		 "exited with #{status.exitstatus}"
	       else
		 "kill by #{status.termsig}"
	       end
      super "#{cmdline}: #{reason}"
    end

    # External program command line as an array of string.
    attr_reader :cmdline
    # External program exit status, as Process:Status
    attr_reader :status
  end

  def self.__check_command_status(cmd) # :nodoc:
    unless $?.success?
      if @@on_command_error != IGNORE
	err = CommandError.new(cmd, $?)
	case @@on_command_error
	when WARN
	  $stderr.puts "Hysh: Command Error: #{err.to_s}"
	when RAISE
	  raise err
	end
      end
      false
    else
      true
    end
  end

  def self.__run(args, options, proc_arg) #:nodoc:
    if proc_arg
      args.first.()
    else
      pid = __spawn args, options, proc_arg
      Process.waitpid pid
      __check_command_status(args)
    end
  end

  # :call-seq:
  #   run() { ... } -> any
  #   run(function) -> any
  #   run(command...[, options]) -> true or false
  #
  # Run the block or the function specified via +function+ and return
  # their return value.  Or run external program specified via
  # +command+ and +options+, +command+ and +options+ are same as that
  # of Process.spawn and return whether external program the exit with
  # 0.  All IO redirections, environment change, current directory
  # change, etc. will take effect when running the block, the function
  # and the external program.
  def self.run(*args_in, &blk)
    __run *__parse_args(args_in, blk)
  end

  def self.__check_close(*ios) # :nodoc:
    ios.each { |io|
      if io && !io.closed?
	io.close
      end
    }
  end

  def self.__popen(stdin, stdout, stderr, args, options, proc_arg) # :nodoc:
    options[:close] = [] if proc_arg

    stdin_in = stdin_out = nil
    stdout_in = stdout_out = nil
    stderr_in = stderr_out = nil
    begin
      if stdin
	stdin_in, stdin_out = IO.pipe
	options[0] = stdin_in
	options[:close].push stdin_out if proc_arg
      end
      if stdout
	stdout_in, stdout_out = IO.pipe
	options[1] = stdout_out
	options[:close].push stdout_in if proc_arg
      end
      if stderr == :stdout
	raise ArgumentError.new unless stdout
	options[2] = stdout_out
      elsif stderr
	stderr_in, stderr_out = IO.pipe
	options[2] = stderr_out
      end
      pid = __spawn args, options, proc_arg
    rescue
      __check_close stdin_out, stdout_in, stderr_in
      raise
    ensure
      __check_close stdin_in, stdout_out, stderr_out
    end
    values = [pid, stdin_out, stdout_in, stderr_in]
    if block_given?
      begin
	yield *values
      ensure
	unless $?.pid == pid
	  Process.detach(pid) rescue nil
	end
	__check_close stdin_out, stdout_in, stderr_in
      end
    else
      values
    end
  end

  # :call-seq:
  #   popen(stdin, stdout, stderr, function) { |pid, stdin_pipe, stdout_pipe, stderr_pipe| ... }
  #   popen(stdin, stdout, stderr, function) -> [pid, stdin_pipe, stdout_pipe, stderr_pipe]
  #   popen(stdin, stdout, stderr, command...[,options]) { |pid, stdin_pipe, stdout_pipe, stderr_pipe| ... }
  #   popen(stdin, stdout, stderr, command...[,options]) -> [pid, stdin_pipe, stdout_pipe, stderr_pipe]
  #
  # Run the function specified via +function+ in a forked sub-process,
  # or run external program specified via +command+ and +options+,
  # +command+ and +options+ are same as that of Process.spawn.
  # Redirect IO as specified via +stdin+, +stdout+, and +stderr+, any
  # non-nil/false value will cause corresponding standard IO to be
  # redirected to a pipe, the other end of pipe will be the block
  # parameters or returned. If the value of +stderr+ argument is
  # :stdout, the standard error will be redirected to standard output.
  #
  # If block is given, the pid and stdin, stdout and stderr pipe will
  # be the parameters for the block.  Popen will return the return
  # value of the block.  The stdin, stdout and sterr pipe will be
  # closed and the process will be detached if necessary upon
  # returning.
  #
  # If no block is given, the pid and stdin, stdout and stderr pipe
  # will be returned.
  def self.popen(stdin, stdout, stderr, *args_in, &blk)
    args, options, proc_arg = __parse_args args_in
    options[:close] = [] if proc_arg

    __popen(stdin, stdout, stderr, args, options, proc_arg, &blk)
  end

  # :section: Glue Processes

  # :call-seq:
  #   pipe(command_line, ...) { ... } -> any
  #   pipe(command_line, ...) -> any or true or false
  #
  # Run multiple functions or external commands specified via
  # +command_line+ and the block, all functions will be run in forked
  # process except the it is specified via the last argument without
  # block or it is specified via the block.  The stdout of the
  # previous command will be connected with the stdin of the next
  # command (the current process if the last argument is function
  # without block or the block), that is, a pipeline is constructed to
  # run the commands.  If the last argument specifies a function
  # without block or there is a block, return the return value of the
  # function or the block.  Otherwise, return the exit success status
  # of the last external program.
  #
  # +command_line+ could be
  #  [command, ..., options]	# command with argument and options in an array
  #  [command, ...]		# command with/without arguments in an array
  #  command			# command without argument
  #  [function]			# function in an array
  #  function			# function
  def self.pipe(*cmds, &blk)
    if block_given?
      cmds.push [blk]
    end
    if cmds.empty?
      raise ArgumentError.new('No argument or block!')
    elsif cmds.size == 1
      __run *__parse_args(cmds.first)
    else
      begin
	pin = pout = prev_pout = last_pin = nil

	last_args, last_options, last_proc_arg = __parse_args cmds.last
	pin, pout = IO.pipe
	if last_proc_arg
	  closefs = [pin]
	  last_pin = pin
	else
	  last_options[0] = pin
	  last_pid = __spawn last_args, last_options, false
	  closefs = []
	  pin.close
	end
	pin = nil

	cmds[1..cmds.size-2].reverse.each { |cmd|
	  args, options, proc_arg = __parse_args cmd
	  prev_pout = pout
	  pout = nil
	  pin, pout = IO.pipe
	  options[0] = pin
	  options[1] = prev_pout
	  if proc_arg
	    options[:close] = closefs + [pout]
	  end
	  pid = __spawn args, options, proc_arg
	  Process.detach pid
	  pin.close
	  pin = nil
	  prev_pout.close
	  prev_pout = nil
	}

	args, options, proc_arg = __parse_args cmds.first
	options[1] = pout
	if proc_arg
	  options[:close] = closefs
	end
	pid = __spawn args, options, proc_arg
	pout.close
	pout = nil
	Process.detach pid

	if last_proc_arg
	  ret = nil
	  with_redirect_stdin_to(last_pin) {
	    ret = __run last_args, last_options, true
	  }
	  last_pin.close
	  last_pin = nil
	  ret
	else
	  Process.waitpid last_pid
	  __check_command_status cmds
	end
      ensure
	__check_close pin, pout, prev_pout, last_pin
      end
    end
  end

  # :call-seq:
  #   run_seq(command_line, ...) { ... } -> any
  #   run_seq(command_line, ...) -> any or true or false
  #
  # Run the functions and the external programs specified via
  # +command_line+, and the block if given, from left to right.
  # +command_line+ is same as that of +pipe+.  Return the return value
  # or exit success status of the last function or external command.
  def self.run_seq(*cmds, &blk)
    if block_given?
      cmds.push blk
    end
    ret = true
    cmds.each { |cmd|
      ret = run(cmd)
    }
    ret
  end

  # :call-seq:
  #   run_or(command_line, ...) { ... } -> any
  #   run_or(command_line, ...) -> any or true or false
  #
  # Run the functions and the external programs specified via
  # +command_line+, and the block if given, from left to right.
  # +command_line+ is same as that of +pipe+.  If any function or
  # block returns non-nil/false, or any external program exits
  # successfully, stop running the remaining function, or external
  # program and return the value.  If all failed, false or nil will be
  # returned.  If no function, external program, or block is given,
  # return false.
  def self.run_or(*cmds, &blk)
    if block_given?
      cmds.push blk
    end
    return false if cmds.empty?

    *head_cmds, last_cmd = cmds
    ignore_on_command_error {
      head_cmds.each { |cmd|
	if ret = run(cmd)
	  return ret
	end
      }
    }
    run(last_cmd)
  end

  # :call-seq:
  #   run_and(command_line, ...) { ... } -> any
  #   run_and(command_line, ...) -> any or true or false
  #
  # Run the functions and the external programs specified via
  # +command_line+, and the block if given, from left to right.
  # +command_line+ is same as that of +pipe+.  If any function or
  # block returns nil or false, or any external program exits failed,
  # stop running the remaining function, or external program and
  # return the value.  If all succeed, return the return value of the
  # last function, the block or the exit success status of the
  # external program.  If no function, external program, or block is
  # provided, return true.
  def self.run_and(*cmds, &blk)
    if block_given?
      cmds.push blk
    end
    return true if cmds.empty?

    *head_cmds, last_cmd = cmds
    ignore_on_command_error {
      head_cmds.each { |cmd|
	unless ret = run(cmd)
	  return ret
	end
      }
    }
    run(last_cmd)
  end

  # :section: Filter Helpers

  # :call-seq:
  #   filter_line() { |line| ... } -> true
  #
  # Feed each line from $stdin to the block, if non-nil/false
  # returned, write the return value to the $stdout.
  def self.filter_line
    $stdin.each_line { |line|
      if ret_line = yield(line)
	$stdout.write ret_line
      end
    }
    true
  end

  # :call-seq:
  #   filter_char() { |char| ... } -> true
  #
  # Feed each character from $stdin to the block, if non-nil/false
  # returned, write the return value to the $stdout.
  def self.filter_char
    $stdin.each_char { |ch|
      if ret_ch = yield(ch)
	$stdout.write ret_ch
      end
    }
    true
  end
end
