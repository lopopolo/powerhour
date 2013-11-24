package Control
{
	import UI.PlayerWrapper;
	
	import com.adobe.serialization.json.JSON;
	
	import flash.events.Event;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	
	import mx.core.Application;

	public class MControl
	{
		public var search_term:String = "";
		
		private var current_stage:uint = 0;
		private var num_stages:uint = 2;
		
		public static function get():MControl {
			return Application.application.control as MControl;
		}
		
		public function next_stage():void {
			current_stage = (current_stage + 1) % num_stages;
			Application.application.viewstack.selectedIndex = current_stage;
		}
		
		public function get_video(number:uint, player:PlayerWrapper):void {
			var videos:Array = new Array("GMmPsNPqIko", "tvorAqnceXQ", "EIRwLLXU9GM");
			//return videos[int(Math.random() * videos.length)];
			
			var loader:VideoDataLoader = new VideoDataLoader();
			loader.addEventListener(Event.COMPLETE, searchCompleteHandler);
			var url:URLRequest = new URLRequest("http://localhost:8000/powerhour/search/"+search_term+"/"+number+"/");
			loader.player = player;
			loader.load(url);
		}
		private function searchCompleteHandler(event:Event):void {
			var loader:VideoDataLoader = VideoDataLoader(event.target);
			trace("completeHandler: " + loader.data);
			var json:Object = JSON.decode(loader.data);
			var id:String = json.id as String;
			loader.player.load_video(id);
		}

	}
}