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

// PaletteSelector.as
// John Maloney, August 2009
//
// PaletteSelector is a UI widget that holds set of PaletteSelectorItems
// and supports changing the selected category. When the category is changed,
// the blocks palette is filled with the blocks for the selected category.

package ui {
	import flash.display.DisplayObject;
	import flash.display.Graphics;
	import flash.display.Sprite;
	import flash.geom.ColorTransform;
	
	import blocks.Block;
	
	import scratch.ScratchSprite;
	import scratch.ScratchStage;
	
	import translation.Translator;

public class PaletteSelector extends Sprite {

	static public function canUseInArduinoMode(category:int):Boolean
	{
		switch(category)
		{
			case Specs.penCategory:
			/*	
			case Specs.looksCategory:
			case Specs.controlCategory:
			case Specs.operatorsCategory:
			case Specs.dataCategory:
			case Specs.myBlocksCategory:*/
				return false;
		}
		return true;
	}
	
	private static const categories:Array = [
		'Motion', 'Looks', 'Sound', 'Pen', 'Data&Blocks', // column 1
		'Events', 'Control', 'Sensing', 'Operators', 'External']; // column 2

	public var selectedCategory:int = 0;
	private var app:eBlock;

	public function PaletteSelector(app:eBlock) {
		this.app = app;
		initCategories();
	}

	public static function strings():Array { return categories }
	public function updateTranslation():void { initCategories() }

	public function select(id:int, shiftKey:Boolean = false):void {
		for (var i:int = 0; i < numChildren; i++) {
			var item:PaletteSelectorItem = getChildAt(i) as PaletteSelectorItem;
			item.setSelected(item.categoryID == id);
			if(app.stageIsArduino){
				item.setEnable(canUseInArduinoMode(item.categoryID));
			}else{
				if(item.categoryID == Specs.motionCategory){
					item.setEnable(app.viewedObj() is ScratchSprite);
				}else{
					item.setEnable(true);
				}
			}
		}
		var oldID:int = selectedCategory;
		selectedCategory = id;
		app.getPaletteBuilder().showBlocksForCategory(selectedCategory, (id != oldID), shiftKey);
		//??????????????????Arudino????????????????????????????????????whenButtonPressed??????????????????
		if(app.stageIsArduino)
		{
			for (var k:int=0;k< app.palette.numChildren;k++)
			{
				var b:Block = app.palette.getChildAt(k) as Block;
				/*if(b && b.op.indexOf("whenButtonPressed")>-1)
				{
					var trans:ColorTransform = new ColorTransform();
					trans.color = 0x999999;
					b.base.transform.colorTransform = trans;
					b.mouseEnabled = false;
					b.mouseChildren = false;
				}*/
			}
		}
		
	}

	private function initCategories():void {
		const numberOfRows:int = 5;
		const w:int = 208+60;
		const startY:int = 3;
		var itemH:int;
		var x:int, i:int;
		var y:int = startY;
		while (numChildren > 0) removeChildAt(0); // remove old contents

		for (i = 0; i < categories.length; i++) {
			if (i == numberOfRows) {
				x = (w / 2) - 3;
				y = startY;
			}
			var entry:Array = Specs.entryForCategory(categories[i]);
			var item:PaletteSelectorItem = new PaletteSelectorItem(entry[0], Translator.map(entry[1]), entry[2]);
			itemH = item.height;
			item.x = x;
			item.y = y;
			addChild(item);
			y += itemH;
		}
		setWidthHeightColor(w, startY + (numberOfRows * itemH) + 5);
	}

	private function setWidthHeightColor(w:int, h:int):void {
		var g:Graphics = graphics;
		g.clear();
		g.beginFill(0x000000, 0); // invisible (alpha = 0) rectangle used to set size
		g.drawRect(0, 0, w, h);
	}

}}
