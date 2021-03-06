/*
 * Scratch Project Editor and Player
 * Copyright (C) 2014 Massachusetts Institute of Technology
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// ExtensionManager.as
// John Maloney, September 2011
//
// Scratch extension manager. Maintains a dictionary of all extensions in use and manages
// socket-based communications with local and server-based extension helper applications.

package extensions {
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.SecurityErrorEvent;
import flash.filesystem.File;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.utils.Dictionary;
import flash.utils.getTimer;
import flash.utils.setTimeout;

import blocks.Block;

import cc.customcode.interpreter.RemoteCallMgr;
import cc.customcode.uibot.uiwidgets.extensionMgr.ExtensionUtil;
import cc.customcode.util.FileUtil;

import translation.Translator;

import uiwidgets.IndicatorLight;

import util.ApplicationManager;
import util.JSON;
import util.LogManager;
import util.ReadStream;
import util.SharedObjectManager;




public class ExtensionManager {

	private var app:eBlock;
	private var extensionDict:Object = new Object(); //Selected Extensions:  extension name -> extension record
	private var justStartedWait:Boolean;
	static public const wedoExt:String = 'LEGO WeDo';

	public var ShowScratchBlocks:Boolean = true;
	
	
	public function ExtensionManager(app:eBlock) {
		this.app = app;
		clearSelectedExtensions();
	}

	public function extensionActive(extName:String):Boolean {
		return extensionDict.hasOwnProperty(extName);
	}

	public function isInternal(extName:String):Boolean {
		return (extensionDict.hasOwnProperty(extName) && extensionDict[extName].isInternal);
	}

	public function clearSelectedExtensions():void {
		// Clear imported extensions before loading a new project.
		extensionDict = {};
	}

	static public function catIdFromSpec(spec:String):int{
   		spec = spec.toLowerCase();
		
		if(spec=="motion") return 1;
		if(spec=="looks") return 2;
		if(spec=="sound") return 3;
		if(spec=="events") return 5;
		if(spec=="sensing") return 7;
		if(spec=="external") return 10;
	   
		return 10;
   }
	
	public  function getBlocksOverride( ext: ScratchExtension ): Array{
		
		if(ext.name == "_base_") return ext.blockSpecs;
		
		var deviceExt: ScratchExtension = this.extensionByName("_base_");
		if(deviceExt==null )return ext.blockSpecs;
		var deviceBlocks:Array = deviceExt.blockSpecs.slice(0);
		
			
		
		
		var tmp:Array = [];
		for each (var spec:Array in ext.blockSpecs) {
			tmp.push(spec);
			
			if (spec.length < 3 && spec[0]== 'category' || spec[0]=='-') continue;
			
			
			//if(spec[2] =="")
			//- si este bloque se llama como alguno de la extension base deviceExt, esporque estamos haciendo un override, lo elimino entonces
			for( var i:int=0; i<deviceBlocks.length; i++) {
				if(spec[2]== deviceBlocks[i][2] || spec[2] == "_base_." + deviceBlocks[i][2] || "_base_."+spec[2] ==  deviceBlocks[i][2]  ){
					deviceBlocks.splice(i,1 );
					break;
				}
			}
		}
		
		//- para no duplicar los bloques
		//if(ext.name == "_base_") return tmp;
		
		//- a??ado los bloques que queden de la extensi??n base
		for each (spec in deviceBlocks) {
			if ( spec.length < 3 && spec[0]== 'category' || spec[0]=='-' ){
				
			}else{
				if( spec[2].indexOf("_base_.")== -1 ) spec[2]= "_base_."+ spec[2];
				
				var blockName:String =  spec[2];
				blockName = blockName.replace("_base_.", "");
				
				if( ext.removeFromBase.indexOf( blockName ) >=0  ) continue; // para no a??adir los bloques marcados a eliminar en una extension heredada
			}
		
				
			tmp.push(spec);
		}
		
		
		
		return tmp;
	}
	
	public function isCallbackForBlock( callBackId:int, blk:Block):Boolean{
	//<- ScratchRuntime	
		
		//- no pertenece a una extensi??n  ??????  ojo,  revisar que los bloques de _base_  vengan con el prefijo
		if(blk.op.indexOf(".")==-1 ) return false;
		
		var extName:String = blk.op.split(".")[0];
		var callBackName:String = blk.op.split(".")[1];
		
		//- construyo el nombe del callback completo a partir de sus argumentos  whenButton_A_pressed
		for each( var arg:*  in blk.args){
			callBackName += "_"+ arg.argValue;
		}
		
		callBackName=callBackName.replace(" ", "_").replace("=", "eq").replace(">", "gt").replace("<", "lt").replace("-", "_").replace("/", "_");
		
		//- busco si coincide el ID del callback que se ejecuta actualmente con el el nombre del callback registrado en la extension ( seccion callbacks:{})
		for each (var ext:ScratchExtension in extensionDict) {
			if( ext.name!= extName ) continue;
			
			if( ext.callbacks[callBackId] == callBackName ) return true;
			
			//if( ext.)
		
		}
		
	   return false;
	}
	
	
	// -----------------------------
	// Block Specifications
	//------------------------------
	public function specForCmd(op:String):Array {
		
		var blockCat:int  =  10;
		
		var blockCandidateInbase:Array=[]; //- por si no encontramos el bloque en su extension pero si est?? en base
		
		
		// Return a command spec array for the given operation or null.
		var count:int=0;
		for each (var ext:ScratchExtension in extensionDict) {
			var prefix:String = ext.useScratchPrimitives ? '' : (ext.name + '.');
		//	trace(count++);
			for each (var spec:Array in ext.blockSpecs) {
				if(spec.length <= 2){
					
					//*JC* bloques en categorias
					if (spec[0]== 'category'){
						blockCat =catIdFromSpec(spec[1]);// Number(spec[1]);
					}
					
					continue;
				}
				
				if(ext.name =="_base_"){ // op siempre vendr?? como  _base_.runDigital  y spec[2]  como _base_.runDigital
					if ( spec[2] == op) {
						//return [spec[1], spec[0], Specs.extensionsCategory, prefix + spec[2], spec.slice(3)];
						blockCandidateInbase = [spec[1], spec[0], blockCat, spec[2], spec.slice(3)];
					}
					
					//- puede que ese bloque  Device.runArduino de otra extension sea compatible con uno de la extension _base_.runARduino
					if(op.split(".")[0]!= "_base_" &&  op.indexOf(".")>0 &&  op.split(".")[1]== spec[2].split(".")[1]){
						blockCandidateInbase =  [spec[1], spec[0], blockCat, spec[2], spec.slice(3)];
					}
					//- o que venga con prefijo de Device.runArduino y  la de _base_ est?? tdavia sin prejijo  "runArduino
					if(op.split(".")[0]!= "_base_" &&  op.indexOf(".")>0 && op.split(".")[1]== spec[2]){
						blockCandidateInbase =  [spec[1], spec[0], blockCat, "_base_."+spec[2], spec.slice(3)];
					}
					
					
				}else if(isCommonExt(ext.name)){
					if ((prefix + spec[2]) == op) {
						//return [spec[1], spec[0], Specs.extensionsCategory, prefix + spec[2], spec.slice(3)];
						return [spec[1], spec[0], blockCat, prefix + spec[2], spec.slice(3)];
					}
				}else{
					if(op.split(".")[1] == spec[2]){
						//return [spec[1], spec[0], Specs.extensionsCategory, prefix + spec[2], spec.slice(3)];
						return [spec[1], spec[0], blockCat, prefix + spec[2], spec.slice(3)];
					}
				}
			}
		}
		
		
		if(blockCandidateInbase.length>0) return blockCandidateInbase;
		
		return null;
	}

	// -----------------------------
	// Enable/disable/reset
	//------------------------------

	public function setEnabled(extName:String, flag:Boolean):void {
		var ext:ScratchExtension = extensionDict[extName];
		if (ext && ext.showBlocks != flag) {
			ext.showBlocks = flag;
		}
	}

	public function isEnabled(extName:String):Boolean {
		var ext:ScratchExtension = extensionDict[extName];
		return ext ? ext.showBlocks : false;
	}

	public function enabledExtensions():Array {
		
		// Answer an array of enabled extensions, sorted alphabetically.
		var result:Array = [];
		var ext:ScratchExtension;
		for each (ext in extensionDict) {
			result.push(ext);
		}
		result.sortOn('sort');
		return result;
	}
	public function allExtensions():Array {
		// Answer an array of enabled extensions, sorted alphabetically.
		var result:Array = [];
		var ext:ScratchExtension;
		for each (ext in extensionDict) {
			result.push(ext);
		}
		result.sortOn('sort');
		return result;
	}
	public function extensionByName(extName:String):ScratchExtension{
		var ext:ScratchExtension = extensionDict[extName];
		return ext;
	}
	public function stopButtonPressed():* {
		// Send a reset_all command to all active extensions.
		var args:Array = [];
		for each (var ext:ScratchExtension in enabledExtensions()) {
			ext.js.call('resetAll', args, ext);
//			RemoteCallMgr.Instance.call(null, 'resetAll', args, ext);
		}
	}

	// -----------------------------
	// Importing
	//------------------------------
	public function openExtensionMenu(e):void{
		
	}
	private var _extensionList:Array = [];
	public function get extensionList():Array{
		return _extensionList;
	}
	public function onSelectExtension(name:String):void{
		if(name=="_import_"){
			return;
		}
	
		var ext:Object = findExtensionByName(name);
		if(null == ext){
			return;
		}
		var extensionSelected:Boolean = !checkExtensionSelected(name);
//		if(isCommonExt(name)){
			SharedObjectManager.sharedManager().setObject(name+"_selected",extensionSelected);
			if(extensionSelected){
				loadRawExtension(ext);
				if(SerialDevice.sharedDevice().connected){
					setTimeout(ConnectionManager.sharedManager().onReOpen,1000);
				}
			}else{
				unloadRawExtension(ext);
			}
			/*
		}else if(extensionSelected){
			for each(var tempExt:Object in _extensionList){
				var extName:String = tempExt.extensionName;
				if(isCommonExt(extName)){
					continue;
				}
				if(checkExtensionSelected(extName)){
					SharedObjectManager.sharedManager().setObject(extName+"_selected",false);
					ConnectionManager.sharedManager().onRemoved(extName);
					delete extensionDict[extName];
				}
			}
			SharedObjectManager.sharedManager().setObject(name+"_selected",true);
			loadRawExtension(ext);
		}
			*/
	}
	static public function isCommonExt(extName:String):Boolean
	{
		switch(extName){
			case "Arduino":
			case "_base_":
			case "Communication":
			case "Joystick(Arduino Mode Only)":
				return true;
		}
		return false;
	}
	static public function isBoardExt(extName:String):Boolean
	{
		var ext:Object = eBlock.app.extensionManager.findExtensionByName(extName);
		return ext != null && (ext.isExtensionBoard || ext.isMakeBlockBoard);
	}
	public function singleSelectExtension(name:String):void{
		var ext:Object = findExtensionByName(name);
		if(null == ext){
			return;
		}
		for each(var tempExt:Object in _extensionList){
			var extName:String = tempExt.extensionName;
			/*if(!isBoardExt(extName)){
				continue;
			}
			*/
			//- deselect extension
			if(checkExtensionSelected(extName)){
				SharedObjectManager.sharedManager().setObject(extName+"_selected",false);
				ConnectionManager.sharedManager().onRemoved(extName);
				delete extensionDict[extName];
			}
		}
		SharedObjectManager.sharedManager().setObject(name+"_selected",true);
		loadRawExtension(ext);
	}
	public function findExtensionByName(name:String):Object{
		for each(var ext:Object in _extensionList){
			if(ext.extensionName==name){
				return ext;
			}
		}
		return null;
	}
	public function checkExtensionSelected(name:String):Boolean{
		return SharedObjectManager.sharedManager().getObject(name+"_selected",false);
	}
	public function checkExtensionEnabled():Boolean{
		var list:Array = extensionList;
		for(var i:uint=0;i<list.length;i++){
			var n:String = list[i].extensionName;
			if(checkExtensionSelected(n)){
				return true;
			}
		}
		return false;
	}
	/*
	private function refreshList():void{
		_extensionList = [];
		if(ApplicationManager.sharedManager().documents.resolvePath("mBlock/libraries/").exists){
			var docs:Array =  ApplicationManager.sharedManager().documents.resolvePath("mBlock/libraries/").getDirectoryListing();
			for each(var doc:File in docs){
				if(!doc.isDirectory){
					continue;
				}
				var fs:Array = doc.getDirectoryListing();
				for each(var f:File in fs){ 
					if(f.extension=="s2e"||f.extension=="json"){
						function onLoadedFile(evt:Event):void{
							var extObj:Object;
							try {
								extObj = util.JSON.parse(evt.target.data.toString());
								var ldr:MeURLLoader = evt.target as MeURLLoader;
								_extensionList.push(extObj);
							} catch(e:*) {}
						}
						var urlloader:MeURLLoader = new MeURLLoader();
						urlloader.addEventListener(Event.COMPLETE,onLoadedFile);
						urlloader.url = f.url;
						urlloader.load(new URLRequest(f.url));
					}
				}
			}
		}
	}
	*/
	public function copyLocalExtensionFiles():void{
		//trace("copyLocalExtensionFiles");
		copyDir("resources/extensions");
	
		/*
		var srcFile:File = File.applicationDirectory.resolvePath("ext/libraries/");
		for each(var sf:File in srcFile.getDirectoryListing()){
			var tf:File = ApplicationManager.sharedManager().documents.resolvePath("mBlock/libraries/"+sf.name);
			if(!tf.exists){
				sf.copyTo(tf,true);
			}else{
				//trace(sf.modificationDate.time-tf.modificationDate.time);
				//if(sf.modificationDate.time>tf.modificationDate.time){
					trace("copy files:",sf.nativePath,tf.nativePath);
					sf.copyTo(tf,true);
				//}
			}
		}
		*/
	}
	public function copyLocalFiles():void{
		LogManager.sharedManager().log("copy local files...");
		copyLocalExtensionFiles();    
		copyFirmwareAndHex();
		//copyDir("media/mediaLibrary.json");
	}
	
	//-
	public function loadExtensionFromJSON( extObj:Object ):void{
		
		_extensionList.push(extObj);
		if(checkExtensionSelected(extObj.extensionName)){
			loadRawExtension(extObj);
		}
		
	} 
	
	public function importExtension():void {
		_extensionList = []; //- All imported extensions
		
		extensionDict = {}; //- Only selected Extensions
		
		//if(ApplicationManager.sharedManager().documents.resolvePath("mblock/resources/extensions/").exists){  //*JC*
		if(ExtensionUtil.extensionPath.exists){  
			var docs:Array = ExtensionUtil.extensionPath.getDirectoryListing();
			//var docs:Array =  ApplicationManager.sharedManager().documents.resolvePath("mblock/resources/extensions/").getDirectoryListing();
			for each(var doc:File in docs){
				if(!doc.isDirectory){
					continue;
				}
				var fs:Array = doc.getDirectoryListing();
				for each(var f:File in fs){
					if(f.extension=="s2e"||f.extension=="json"){
						var extObj:Object = util.JSON.parse(FileUtil.ReadString(f));
						extObj.srcPath = f.url;
						loadExtensionFromJSON( extObj );
					}
				}
				_extensionList.sortOn("sort", Array.NUMERIC);
			}
		}else{
			if(SharedObjectManager.sharedManager().available("first-launch")){
				SharedObjectManager.sharedManager().clear();
				SerialManager.sharedManager().device = "uno";
			}else{
			}
		}
		
		return;
//		var fs:Array =  File.applicationDirectory.resolvePath("ext/").getDirectoryListing();
//		for each(var f:File in fs){ 
//			if(f.extension=="s2e"||f.extension=="json"){
//				function onLoadedFile(evt:Event):void{
//					var extObj:Object;
//					try {
//						extObj = util.JSON.parse(evt.target.data.toString());
//						loadRawExtension(extObj);
//					} catch(e:*) {}
//				}
//				var urlloader:URLLoader = new URLLoader();
//				urlloader.addEventListener(Event.COMPLETE,onLoadedFile);
//				urlloader.load(new URLRequest(f.nativePath));
//			}
//		}
		
		
	}
	private function copyFirmwareAndHex():void{
	
		//copyDir("firmware");
		//copyDir("resources/boards");
		//copyDir("locale"); //*JC* portable
	}
	
	static private function copyDir(dirName:String, destDirName:String=null):void
	{
		var fromFile:File = File.applicationDirectory.resolvePath(dirName);
		
		//var toFile:File = File.applicationStorageDirectory.resolvePath("mBlock").resolvePath(destDirName || dirName);
		var toFile:File = File.applicationStorageDirectory.resolvePath("appfiles").resolvePath(destDirName || dirName);
		
		fromFile.copyTo(toFile, true);
	}
	
	public function extensionsToSave():Array {
		// Answer an array of extension descriptor objects for imported extensions to be saved with the project.
		var result:Array = [];
		for each (var ext:ScratchExtension in extensionDict) {
			if(!ext.showBlocks) continue;

			var descriptor:Object = {};
			descriptor.extensionName = ext.name;
			descriptor.blockSpecs = ext.blockSpecs;
			descriptor.menus = ext.menus;
			if(ext.port) descriptor.extensionPort = ext.port;
			else if(ext.javascriptURL) descriptor.javascriptURL = ext.javascriptURL;
			result.push(descriptor);
		}
		return result;
	}

	public function callCompleted(extensionName:String, id:Number):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null) return; // unknown extension

		var index:int = ext.busy.indexOf(id);
		if(index > -1) ext.busy.splice(index, 1);
	}

	public function reporterCompleted(extensionName:String, id:Number, retval:*):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null) return; // unknown extension
//		var maxIndex:int = ext.busy.indexOf(id);
//		if(maxIndex > -1) {
//			for(var index:uint=0;index<=maxIndex;index++){
//				ext.busy.splice(index, 1);
				for(var b:Object in ext.waiting) {
					var block:Block = b as Block;
					if(ext.waiting[b] === id) {
						delete ext.waiting[b];
						if(retval != null){
							//if(block.response!=retval){
//								block.nextID = [];
								block.response = retval;
								block.requestState = 2;
//								MBlock_mod.app.runtime.exitRequest();
							//}
						}
					}
				}
//			}
//		}
	}
    
	
	
	public function getCallbackId( extname:String, callbackname:String):int{
		
	
		
		var ext:ScratchExtension = extensionDict[extname];
		
		if(ext ==null) return 0;
		
		var callback:Object = (ext.callbacks);
		
		
		for (var k:int in  callback){
			if( callback[k] == callbackname ) return k;
		}
		
		
		return 0;
	}
	
	
	public function loadCheckedExtensions():void{
		var list:Array = [];
		
		list = extensionList;
		
		for(var i:int=0;i<list.length;i++){
			var extName:String = list[i].extensionName;
			
			//this.unloadRawExtension(list[i]);
			//onSelectExtension(extName);
			if(this.checkExtensionSelected(extName)){
				//this.unloadRawExtension(list[i]);
				
				this.loadRawExtension(list[i]);
			}
			
		}
	}
	
	public function loadRawExtension(extObj:Object):void {
	
		var ext:ScratchExtension = extensionDict[extObj.extensionName];  //- intento cargarla o la creo null
		if(ext)	return;
		
		if(!ext || (ext.blockSpecs && ext.blockSpecs.length)){
			ext = new ScratchExtension(extObj.extensionName, extObj.extensionPort);
		}
		
		if(extObj.url) ext.url = extObj.url;
		if(extObj.extensionHost) ext.host = extObj.extensionHost;
		if(extObj.extensionType) ext.type = extObj.extensionType;
		var srcArr:Array = extObj.srcPath.split("/");
		ext.docPath = extObj.srcPath.split(srcArr[srcArr.length-1]).join("");
		ext.srcPath = ext.docPath+"/src";
		//ext.showBlocks = true;
		ext.menus = extObj.menus;
		if(extObj.values){
			ext.values = extObj.values;
		}
		if(extObj.removeFromBase){
			ext.removeFromBase = extObj.removeFromBase;
		}
		
		if(extObj.callbacks){
			ext.callbacks = extObj.callbacks;
		}
		
		if(extObj.translators){
			ext.translators = extObj.translators;
		}
		if(extObj.firmware){
			ext.firmware = extObj.firmware;
		}
		ext.javascriptURL = extObj.javascriptURL;	
		if (extObj.host) ext.host = extObj.host; // non-local host allowed but not saved in project
		if(ext.port==0&&ext.javascriptURL!=""){
			ext.useSerial = true;
		}else{
			ext.useSerial = false;
		}
		if(extObj.sort){
			ext.sort = extObj.sort;
		}
		
		ext.blockSpecs = extObj.blockSpecs;
		//- hacemos el Override
		if(extObj.isExtensionBoard ){
			ext.blockSpecs = this.getBlocksOverride(ext);
		}
		
		
		
		//- a??ado el prefijo de la extension a cada bloque
		/*for each (var spec:Array in ext.blockSpecs ) {
			var fullName:String = ext.name+"."+spec[2]; 
			if (spec.length >= 3 && spec[2].indexOf(fullName)==-1) 	spec[2]=fullName;
		}*/
		
 		extensionDict[extObj.extensionName] = ext;
		
		if(extensionDict["Arduino"]){
		//extensionDict["Arduino"]["menus"]["digital"].push("OTHER");
		}
		
		
		
		parseTranslators(ext);
//		parseAllTranslators();
		eBlock.app.translationChanged();
		 eBlock.app.updatePalette();
		// Update the indicator
		for (var i:int = 0; i < app.palette.numChildren; i++) {
			var indicator:IndicatorLight = app.palette.getChildAt(i) as IndicatorLight;
			if (indicator && indicator.target === ext) {
				updateIndicator(indicator, indicator.target, true);
				break;
			}
		}
	}
	
	private function unloadRawExtension(extObj:Object):void{
		ConnectionManager.sharedManager().onRemoved(extObj.extensionName);
		delete extensionDict[extObj.extensionName];
//		parseAllTranslators();
		eBlock.app.translationChanged();
		eBlock.app.updatePalette();
		// Update the indicator
		for (var i:int = 0; i < app.palette.numChildren; i++) {
			var indicator:IndicatorLight = app.palette.getChildAt(i) as IndicatorLight;
			if (indicator && indicator.target === extObj) {
				updateIndicator(indicator, indicator.target, true);
				break;
			}
		}
	}
	public function parseAllTranslators():void{
		for each (var ext:ScratchExtension in extensionDict) {
			parseTranslators(ext);
		}
	}
	private function parseTranslators(ext:ScratchExtension):void{
		if(null == ext.translators){
			return;
		}
		for(var key:String in ext.translators){
			if(Translator.currentLang != key){
				continue;
			}
			var dict:Object = ext.translators[key];
			for(var entryKey:String in dict){
				Translator.addEntry(entryKey,dict[entryKey]);
			}
			break;
		}
	}
	public function loadSavedExtensions(savedExtensions:Array):void {
		// Reset the system extensions and load the given array of saved extensions.
		for each (var extObj:Object in savedExtensions) {
			if (!('extensionName' in extObj)) {
				continue;
			}
			if(!checkExtensionSelected(extObj.extensionName)){
				onSelectExtension(extObj.extensionName);
			}
		}

	}

	// -----------------------------
	// Menu Support
	//------------------------------

	public function menuItemsFor(op:String, menuName:String):Array {
		// Return a list of menu items for the given menu of the extension associated with op or null.
		var i:int = op.lastIndexOf('.');
		if (i < 0) return null;
		var ext:ScratchExtension = extensionDict[op.slice(0, i)];
		if (ext == null) return null; // unknown extension
		return ext.menus[menuName];
	}

	// -----------------------------
	// Status Indicator
	//------------------------------

	public function updateIndicator(indicator:IndicatorLight, ext:ScratchExtension, firstTime:Boolean = false):void {
		var msecsSinceLastResponse:uint = getTimer() - ext.lastPollResponseTime;
		
		//eBlock.app.extensionManager.
		
		if(ext.useSerial){
			if (!SerialDevice.sharedDevice().connected) {
				//indicator.setColorAndMsg(0xE00000, Translator.map('Disconnected'));
				
				//this.app.topBarPart.updateIndicator( false );
//				MBlock_mod.app.topBarPart.setBluetoothTitle(false);
			}
			else if (ext.problem != '') {
				//this.app.topBarPart.updateIndicator( false );
				//indicator.setColorAndMsg(0xE0E000, ext.problem);
			}
			else {
				//this.app.topBarPart.updateIndicator( true );
				//indicator.setColorAndMsg(0x00C000, ext.success);
			}
		}else{
			if (msecsSinceLastResponse > 500){
				//this.app.topBarPart.updateIndicator( false );
				//indicator.setColorAndMsg(0xE00000, Translator.map('Disconnected'));
			}
			else if (ext.problem != '') {
				//this.app.topBarPart.updateIndicator( false );
				//indicator.setColorAndMsg(0xE0E000, ext.problem);
			}
			else{
				//this.app.topBarPart.updateIndicator( true );
				//indicator.setColorAndMsg(0x00C000, ext.success);
			}
		}
		
	}

	// -----------------------------
	// Execution
	//------------------------------
/*
	public function primExtensionOp(b:Block):* {
		
		var i:int = b.op.indexOf('.');
		var extName:String = b.op.slice(0, i);
		var ext:ScratchExtension = extensionDict[extName];
		if (ext == null) return 0; // unknown extension
		var primOrVarName:String = b.op.slice(i + 1);
		var args:Array = [];
		for (i = 0; i < b.args.length; i++) {
			args.push(app.interp.arg(b, i));
		}
		var value:*;
		
		if (b.isReporter) {
			if(b.isRequester){
//				if(b.requestState == 2) {
//					b.requestState = 0;
//				}else{
					request(extName, primOrVarName, args, b);
//					b.requestState = 0;
//					return b.response;
//				}
				// Returns null if we just made a request or we're still waiting
				return b.response;//==null?0:b.response;
			}else{
				var sensorName:String = primOrVarName;
				if(ext.port > 0) {  // we were checking ext.isInternal before, should we?
					sensorName = encodeURIComponent(sensorName);
					for each (var a:* in args) {
						sensorName += '/' + encodeURIComponent(a); // append menu args
					}
//					trace("sensor:",sensorName);
					value = ext.stateVars[sensorName];
				}
				if(ext.useSerial){
					value = ParseManager.sharedManager().getFirstLine();
					if(sensorName.indexOf("serial/read/line")>-1){
						
					}else if(sensorName.indexOf("serial/read/command")>-1){
						value = ParseManager.sharedManager().getCommand(args[0]);
					}
				}
				if (value == undefined) value = 0; // default to zero if missing
				if ('b' == b.type) value = (ext.port>0 ? 'true' == value : true == value); // coerce value to a boolean
				return value;
			}
		} else {
//			if ('w' == b.type) {
//				var activeThread:Thread = app.interp.activeThread;
//				if (activeThread.firstTime) {
//					var id:int = ++ext.nextID; // assign a unique ID for this call
//					ext.busy.push(id);
//					activeThread.tmp = id;
//					app.interp.doYield();
//					justStartedWait = true;
//					//args.unshift(id); // pass the ID as the first argument
//				} else {
//					if (ext.busy.indexOf(activeThread.tmp) > -1) {
//						app.interp.doYield();
//					} else {
//						activeThread.tmp = 0;
//						activeThread.firstTime = true;
//					}
//					return;
//				}
//			}
			call(extName, primOrVarName, args);
		}
	}
*/
	public function call(extensionName:String, op:String, args:Array):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		
		if (ext == null) return; // unknown extension
		
//		var activeThread:Thread = app.interp.activeThread;
//		if(activeThread && op != 'resetAll') {
//			if(activeThread.firstTime) {
//				httpCall(ext, op, args);
//				activeThread.firstTime = false;
//				app.interp.doYield();
//			}
//			else {
//				activeThread.firstTime = true;
//			}
//		}else{
			httpCall(ext, op, args);
//		}
		
	}

	public function request(extensionName:String, op:String, args:Array, b:Block):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null||(ext.useSerial&&!SerialDevice.sharedDevice().connected)||app.runtime.isRequest){
			// unknown extension, skip the block
//			b.requestState = 2;
//			b.response = 0;
			return;
		}
		if(ext.javascriptURL==null){
			httpRequest(ext, op, args, b);
		}else{
//			++ext.nextID;
//			ext.busy.push(ext.nextID);
			
			if(b in ext.waiting){
//				ext.js.requestValue(op,args,ext,ext.waiting[b]);
			}else{
				ext.waiting[b] = ++ext.nextID;
//				ext.js.requestValue(op,args,ext, ext.nextID);
				if(ext.nextID>50){
					ext.nextID = 0;
				}
			}
			
			
//			ext.waiting[b] = ext.nextID;
//			b.nextID.push(ext.nextID);
//			MBlock_mod.app.runtime.enterRequest();
//			ext.js.requestValue(op,args,ext);
//			if(ext.nextID>50){
//				ext.nextID = 0;
//			}
			//'ScratchExtensions.getReporterAsync', ext.name, op, args, ext.nextID);
		}
//		if (ext.port > 0) {
//			
//		} else if(MBlock_mod.app.jsEnabled) {
//			// call a JavaScript extension function with the given arguments
//			b.requestState = 1;
//			++ext.nextID;
//			ext.busy.push(ext.nextID);
//			ext.waiting[b] = ext.nextID;
//			ExternalInterface.call('ScratchExtensions.getReporterAsync', ext.name, op, args, ext.nextID);
//		}
	}

	private function httpRequest(ext:ScratchExtension, op:String, args:Array, b:Block):void {
		var url:String;
		if(ext.useSerial){
			++ext.nextID;
			if(ext.nextID>41){
				ext.nextID = 0;
			}
			ext.busy.push(ext.nextID);
			ext.waiting[b] = ext.nextID;
//			b.nextID.push(ext.nextID);
			url = ''+op;
			for each (var arg:* in args) {
				url += '/' + ((arg is String) ? escape(arg) : arg);
			}
			//url+='/Ext'+ext.nextID;
			
			b.requestState = 1;
			eBlock.app.runtime.enterRequest();
			ParseManager.sharedManager().extNames[ext.nextID] = ext.name;
			var objs:Array = eBlock.app.extensionManager.specForCmd(ext.name+"."+op);
			var obj:Object = objs[objs.length-1];
			obj = obj[obj.length-1];
			if(obj!=null && obj.encode!="" && obj.encode!=null){
				ParseManager.sharedManager().parseEncode(url,obj.encode,ext.nextID,args,ext);
			}else{
				ParseManager.sharedManager().parse(url);
			}
			
		}else{
			function responseHandler(e:Event):void {
				if(e.type == Event.COMPLETE)
					b.response = loader.data;
				else
					b.response = '';
				b.requestState = 2;
				b.requestLoader = null;
				eBlock.app.runtime.exitRequest();
			}
			var loader:URLLoader = new URLLoader();
			loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, responseHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, responseHandler);
			loader.addEventListener(Event.COMPLETE, responseHandler);
			
			b.requestState = 1;
			b.requestLoader = loader;
			
			url = 'http://' + ext.host + ':' + ext.port + '/' + encodeURIComponent(op);
			for each (arg in args) {
				url += '/' + ((arg is String) ? encodeURIComponent(arg) : arg);
			}
			loader.load(new URLRequest(url));
			
			eBlock.app.runtime.enterRequest();
		}
	}

	private function httpCall(ext:ScratchExtension, op:String, args:Array):void {
		function errorHandler(e:Event):void { } // ignore errors
		var url:String ;
		var arg:*;
//		if(ext.useSerial){
//			url = '' + op;
//			for each ( arg in args) {
//				url += '/' + ((arg is String) ? escape(arg) : arg);
//			}
//			var objs:Array = MBlock_mod.app.extensionManager.specForCmd(ext.name+"."+op);
//			if(op.indexOf("resetAll")>-1){
//				ParseManager.sharedManager().parse("resetAll");
//			}
//			if(objs==null){
//				return;
//			}
//			var obj:Object = objs[objs.length-1];
//			obj = obj[obj.length-1];
//			++ext.nextID;
//			if(obj!=null && obj.encode!="" && obj.encode!=null){
//				ParseManager.sharedManager().parseEncode(url,obj.encode,ext.nextID,args,ext);
//			}else{
//				ParseManager.sharedManager().parse(url);
//			}
//		}else{
			if(!ext.js){
				url = 'http://' + ext.host + ':' + ext.port + '/' + encodeURIComponent(op);
				for each ( arg in args) {
					url += '/' + ((arg is String) ? encodeURIComponent(arg) : arg);
				}
				var loader:URLLoader = new URLLoader();
				loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
				loader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
				loader.load(new URLRequest(url));
			}else{
				ext.js.call(op,args,ext);
			}
//		}
//		var loader:URLLoader = new URLLoader();
//		loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
//		loader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
//		loader.load(new URLRequest(url));
	}
	
	public function getStateVar(extensionName:String, varName:String, defaultValue:*):* {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null) return defaultValue; // unknown extension
		var value:* = ext.stateVars[varName];
		return (value == undefined) ? defaultValue : value;
	}

	// -----------------------------
	// Polling
	//------------------------------

	public function step():void {
		// Poll all extensions.
		for each (var ext:ScratchExtension in extensionDict) {
			if (ext.showBlocks) {
//				if (ext.blockSpecs.length == 0) httpGetSpecs(ext);
				if((!ext.isInternal && ext.port > 0&&ext.useSerial==false)){
					httpPoll(ext);
				}
			}
		}
	}

	private function httpPoll(ext:ScratchExtension):void {
		// Poll via HTTP.
		if(ext.isBusy){
			return;
		}
		if(ext.js.connected){
			ext.lastPollResponseTime = getTimer();
			ext.isBusy = false;
			ext.success = "Okay";
			ext.problem = "";
			return;
		}else{
			ext.success = "";
			ext.problem = ext.js.msg;
		}
		function completeHandler(e:Event):void {
			ext.isBusy = false;
			processPollResponse(ext, loader.data);
		}
		function errorHandler(e:Event):void {
			ext.isBusy = false;
		} // ignore errors
		var url:String = 'http://' + ext.host + ':' + ext.port + '/poll';
		var loader:URLLoader = new URLLoader();
		loader.addEventListener(Event.COMPLETE, completeHandler);
		loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
		loader.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
		loader.load(new URLRequest(url));
		ext.isBusy = true;
	}

	private function processPollResponse(ext:ScratchExtension, response:String):void {
		if (response == null) return;
		ext.lastPollResponseTime = getTimer();
		ext.problem = '';

		// clear the busy list unless we just started a command that waits
		if (justStartedWait) justStartedWait = false;
		else ext.busy = [];

		var lines:Array = response.split('\n');
		for each (var line:String in lines) {
			var tokens:Array = ReadStream.tokenize(line);
			if (tokens.length > 1) {
				var key:String = tokens[0];
				if (key.indexOf('_') == 0) { // internal status update or response
					if ('_busy' == key) {
						for (var i:int = 1; i < tokens.length; i++) {
							var id:int = parseInt(tokens[i]);
							if (ext.busy.indexOf(id) == -1) ext.busy.push(id);
						}
					}
					if ('_problem' == key) ext.problem = line.slice(9);
					if ('_success' == key) ext.success = line.slice(9);
				} else { // sensor value
					var val:String = tokens[1];
					var n:Number = Number(val);
					ext.stateVars[key] = isNaN(n) ? val : n;
				}
			}
		}
	}

	}
}