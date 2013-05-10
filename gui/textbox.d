module gui.textbox;

import gui.gui;
import gui.render_box;
import cell.textbox;
import cell.cell;
import text.text;
import misc.direct;
import std.array;
import std.string;
import std.typecons;

import gtk.IMContext;

import cairo.Context;
import cairo.FontOption;
import cairo.Surface;
import cairo.ImageSurface;

import gtkc.pangotypes;
import pango.PgCairo;
import pango.PgLayout;
import pango.PgFontDescription;
import pango.PgAttributeList;

import std.stdio;
import shape.shape;

class RenderTextBOX : BoxRenderer{
private:
    alias int BoxId;
    alias int Line;
    TextBOX render_target; // renderが呼ばれるごとに切り替わる
    TextBOX im_target; // IM使ってであろうBOX
    int im_target_id;

    // stored info to show table
    Rect[BoxId] box_pos;
    PgLayout[Line][BoxId] layout;
    PgFontDescription[BoxId] desc;
    PgAttributeList[BoxId] attrlist;

    string[Line][BoxId] strings;

    int currentline; // preedit のために保持
    string preedit;

    ubyte[BoxId] fontsize;
    int[int][BoxId] width,height;
    Color[BoxId] fontcolor;
    int gridSize;
public:
    this(PageView pv)
    body{
        super(pv);
    }
    
    public void render(Context cr,TextBOX box)
        in{
        assert(!box.empty);
        }
    body{
        debug(gui) writeln("render textbox start");
        // 
        auto box_id = box.get_id();
        gridSize = page_view.get_gridSize();
        box_pos[box_id] = get_position(box); // gui.render_box::get_position
        box_pos[box_id].y += gridSize/3;
        fontsize[box_id] = cast(ubyte)box.font_size;    //  !!TextBOXで変更できるように 
        fontcolor[box_id] = box.font_color;             //  !!なったら変更 
        auto numof_lines = box.getText().numof_lines();
        currentline = box.getText().currentline();
            
        void  modify_boxsize()
        {   // 描画された領域のサイズでBOXを変形させる
            // フォントの大きさを順守するため
            // 1Cell1Charモードならここは通るな通すな

            // 何通りかの挙動が考えられる
            //    1行目の横幅で自動改行
            //    自動expnad <= 下の実装
            //    横に圧縮して無理やり入れる
            //    Cellごと縮小して無理やり入れる
            // 
            // 確定されてBOX はこの処理を通したくない
            // TODO 確定されたBOXの定義
            // auto pre_box = box.get_box_dup();
            if(box_id !in width) return;

            do{
                auto pre_box = box.get_box();

                auto box_width = gridSize * box.numof_hcell();
                debug(gui) writefln("box width %d",box_width);

                auto sorted_width = width[box_id].values.sort;
                auto max_width = sorted_width[$-1];
                // auto min_width = sorted_width[0];

                // expand後の box_widthで揺らがないように調整必要
                // 次のループではbox_widthの大きさは変わってる
                if(max_width > box_width)
                    box.expand(Direct.right); 
                else
                if(max_width < box_width-gridSize)
                {
                    box.remove(Direct.right);
                }

                if(pre_box == box.get_box())
                    break;
            }while(true);
        }
        void render_preedit()
        {
            debug(gui) writeln("render preedit start");
            // if(currentline !in layout)  <- 改行後現れなくなる
            layout[im_target_id][currentline] = PgCairo.createLayout(cr); // 
            layout[im_target_id][currentline].setFontDescription(desc[im_target_id]);

            if( im_target_id !in width || currentline !in width[im_target_id])   // この2つのifまとめられそうだけど精神的衛生上
                width[im_target_id][currentline] = 0;

            layout[im_target_id][currentline].setAttributes(attrlist[im_target_id]);
            layout[im_target_id][currentline].setText(preedit);

            auto fc = fontcolor[box_id]; // 初回のpreeditのため(だけ)に必要
            cr.setSourceRgb(fc.r,fc.g,fc.b);

            cr.moveTo(box_pos[im_target_id].x+width[im_target_id][currentline],box_pos[im_target_id].y+currentline*gridSize);
            PgCairo.updateLayout(cr,layout[im_target_id][currentline]);
            PgCairo.showLayout(cr,layout[im_target_id][currentline]);

            set_preeditting(false);
            debug(gui) writeln("end");
        }
        void checkBOX(TextBOX box)
        {
            debug(gui) writeln("checkBOX start");
            if(render_target != box){

                desc[box_id] = PgFontDescription.fromString(box.get_fontname~fontsize[box_id]);
                render_target = box;

                layout[box_id][0] = PgCairo.createLayout(cr);
                layout[box_id][0].setFontDescription(desc[box_id]);

                auto fc = fontcolor[box_id];
                cr.setSourceRgb(fc.r,fc.g,fc.b);
            }
            debug(gui) writeln("end");
        }
        
        checkBOX(box);
        strings[box_id] = box.getText().strings;
        debug(text) writeln("strings are ",strings[box_id]);

        foreach(line,one_line; strings[box_id])
        {
            if(one_line.empty) break;
            // if(line !in layout) <- IMのpreedit位置が最初の位置にも反映されてしまう
            layout[box_id][line] = PgCairo.createLayout(cr);
            layout[box_id][line].setFontDescription(desc[box_id]);

            debug(gui) writeln("write position: ",box_pos[box_id].x," ",box_pos[box_id].y);
            auto fc = fontcolor[box_id];
            cr.setSourceRgb(fc.r,fc.g,fc.b);

            auto lines_y = box_pos[box_id].y + gridSize * line;
            cr.moveTo(box_pos[box_id].x,lines_y);
            layout[box_id][line].setText(one_line);
            PgCairo.updateLayout(cr,layout[box_id][line]);
            PgCairo.showLayout(cr,layout[box_id][line]);

            // get real using width and height
            // render_preedit より前に取得する必要がある
            layout[box_id][line].getPixelSize(width[box_id][line],height[box_id][line]);
            debug(gui) writefln("layout width %d",width[box_id][line]);

            debug(gui) writefln("wt %s",one_line);
        }

        if(is_preediting() && im_target_id == box_id)
            render_preedit();
        if(!strings[box_id].keys.empty) modify_boxsize();
        debug(gui) writeln("text render end");
    }
    public void prepare_preedit(IMContext imc,ContentBOX inputted_box){
        debug(text) writeln("prepare_preedit start");
        im_target = cast(TextBOX)inputted_box;
        assert(im_target !is null);
        im_target_id = inputted_box.get_id();
        imc.getPreeditString(preedit,attrlist[im_target_id],render_target.cursor_pos);
        set_preeditting(true);
        debug(text) writeln("end");
    }
    public void retrieve_surrouding(IMContext imc){
    }
    private bool preeditting;
    private bool is_preediting(){
        return preeditting;
    }
    private void set_preeditting(bool b){
        preeditting = b;
    }
    public auto get_surrounding(){
        debug(gui) writeln("get surrounding start");
        im_target.cursor_pos = im_target.getText.get_caret().column;
        writeln("cursor_pos: ",im_target.cursor_pos); 
        return tuple(strings[im_target_id][currentline],im_target.cursor_pos);
        debug(gui) writeln("end");
    }
}
 