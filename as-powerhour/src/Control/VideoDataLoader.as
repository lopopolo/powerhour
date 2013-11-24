package Control
{
	import UI.PlayerWrapper;
	
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	
	public class VideoDataLoader extends URLLoader
	{
		public var player:PlayerWrapper;
		
		public function VideoDataLoader(request:URLRequest=null)
		{
			super(request);
		}
	}
}