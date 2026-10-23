namespace GSSystemAnalyzer.Interfaces
{
	public interface IRecycleBinProvider
	{
		void SendFileToRecycleBin(string path);
		void SendDirectoryToRecycleBin(string path);
		bool TryRestore(string originalPath);
	}
}
