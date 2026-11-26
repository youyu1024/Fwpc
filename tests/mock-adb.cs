using System;
using System.IO;
using System.Threading;
using System.Web.Script.Serialization;
using System.Collections.Generic;

internal static class MockAdb
{
    private sealed class Response
    {
        public string output { get; set; }
        public string error { get; set; }
        public string input { get; set; }
        public string bytes { get; set; }
        public int exit { get; set; }
        public int delayMs { get; set; }
    }

    public static int Main(string[] args)
    {
        string root = Environment.GetEnvironmentVariable("FWPC_MOCK_ADB");
        if (String.IsNullOrEmpty(root)) return 100;
        string command = String.Join(" ", args);
        File.AppendAllText(Path.Combine(root, "calls.txt"), command + Environment.NewLine);
        if (args.Length > 1 && args[0] == "--serial")
        {
            Thread.Sleep(30000);
            return 0;
        }

        var serializer = new JavaScriptSerializer();
        string path = Path.Combine(root, "responses.json");
        var responses = serializer.Deserialize<Dictionary<string, List<Response>>>(File.ReadAllText(path));
        List<Response> sequence;
        if (!responses.TryGetValue(command, out sequence) || sequence.Count == 0)
        {
            Console.Error.WriteLine("Unexpected ADB command: " + command);
            return 101;
        }

        Response response = sequence[0];
        if (sequence.Count > 1)
        {
            sequence.RemoveAt(0);
            File.WriteAllText(path, serializer.Serialize(responses));
        }
        if (response.input != null && Console.ReadLine() != response.input)
        {
            Console.Error.WriteLine("Unexpected standard input.");
            return 102;
        }
        if (response.delayMs > 0) Thread.Sleep(response.delayMs);
        if (response.bytes != null)
        {
            byte[] bytes = Convert.FromBase64String(response.bytes);
            Console.OpenStandardOutput().Write(bytes, 0, bytes.Length);
        }
        if (response.output != null) Console.WriteLine(response.output);
        if (response.error != null) Console.Error.WriteLine(response.error);
        return response.exit;
    }
}
