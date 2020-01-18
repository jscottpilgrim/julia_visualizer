using System;
using System.Diagnostics;

namespace ExSpace
{
	class ExClass
	{
		static void ExecuteCommand(string command)
		{
			var processInfo = new ProcessStartInfo("cmd.exe", "/c " + command);
			processInfo.UseShellExecute = false;
			processInfo.CreateNoWindow = true;
			processInfo.RedirectStandardError = true;
			processInfo.RedirectStandardOutput = true;

			var process = Process.Start(processInfo);

			process.OutputDataReceived += (object sender, DataReceivedEventArgs e) =>
				Console.WriteLine("output>>" + e.Data);
			process.BeginOutputReadLine();

			process.ErrorDataReceived += (object sender, DataReceivedEventArgs e) =>
				Console.WriteLine("error>>" + e.Data);
			process.BeginErrorReadLine();

			process.WaitForExit();

			Console.WriteLine("ExitCode: {0}", process.ExitCode);
			process.Close();
		}

		static void Main()
		{
		    ExecuteCommand("jdk-11.0.5+10-jre\\bin\\java.exe -jar jruby_complete\\jruby-complete-9.2.9.0.jar jv\\jv_launcher.rb");
		}
	}
}
