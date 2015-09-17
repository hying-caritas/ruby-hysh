# -*- ruby-indent-level: 2; -*-

require_relative "../lib/hysh"

def dpkg_installed1(package_names = nil)
  Hysh.out_lines ->{
    Hysh.pipe ['dpkg', '-l'],
      if package_names
	['egrep', "(#{package_names.join '|'})"]
      else
	['cat']
      end
  }
end

def dpkg_installed2(package_names = nil)
  Hysh.out_lines ->{
    Hysh.pipe ['dpkg', '-l'] {
      proc_line = if package_names
		    ->l{
		      if package_names.any? { |pkg|
			   l.index pkg
			 }
			l
		      end
		    }
		  else
		    ->l{ l }
		  end
      Hysh.filter_line &proc_line
    }
  }
end
