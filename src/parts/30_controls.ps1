# ============================================================
#  ТЕМА И АНИМИРОВАННЫЕ КОНТРОЛЫ (C#)
# ============================================================
$script:CsCode = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace RustSuite
{
    public interface IAnim { bool Tick(); }

    public static class Anim
    {
        private static readonly List<IAnim> Items = new List<IAnim>();
        private static Timer _timer;

        public static void Add(IAnim a)
        {
            if (a == null) return;
            if (!Items.Contains(a)) Items.Add(a);
            if (_timer == null)
            {
                _timer = new Timer();
                _timer.Interval = 15;
                _timer.Tick += OnTick;
            }
            if (!_timer.Enabled) _timer.Start();
        }

        public static void Remove(IAnim a)
        {
            if (a != null) Items.Remove(a);
            if (Items.Count == 0 && _timer != null) _timer.Stop();
        }

        private static void OnTick(object sender, EventArgs e)
        {
            for (int i = Items.Count - 1; i >= 0; i--)
            {
                bool keep;
                try { keep = Items[i].Tick(); }
                catch { keep = false; }
                if (!keep) Items.RemoveAt(i);
            }
            if (Items.Count == 0 && _timer != null) _timer.Stop();
        }
    }

    public static class Ease
    {
        public static float Clamp01(float v) { return v < 0f ? 0f : (v > 1f ? 1f : v); }
        public static float OutCubic(float t)
        {
            t = Clamp01(t); float u = 1f - t;
            return 1f - u * u * u;
        }
        public static float OutBack(float t)
        {
            t = Clamp01(t); float c1 = 1.70158f; float c3 = c1 + 1f; float u = t - 1f;
            return 1f + c3 * u * u * u + c1 * u * u;
        }
        public static float Approach(float cur, float target, float k)
        {
            return cur + (target - cur) * k;
        }
        public static bool Done(float a, float b) { return Math.Abs(a - b) < 0.002f; }
    }

    public static class Theme
    {
        public static Color Bg        = Color.FromArgb(22, 14, 34);
        public static Color PanelBg   = Color.FromArgb(26, 16, 38);
        public static Color CardBg    = Color.FromArgb(30, 18, 42);
        public static Color CardHover = Color.FromArgb(34, 22, 48);
        public static Color BorderC   = Color.FromArgb(60, 40, 90);
        public static Color Accent    = Color.FromArgb(140, 50, 200);
        public static Color AccentLt  = Color.FromArgb(180, 80, 230);
        public static Color Secondary = Color.FromArgb(255, 70, 190);
        public static Color Glow      = Color.FromArgb(90, 40, 160);
        public static Color TextC     = Color.FromArgb(250, 240, 255);
        public static Color Muted     = Color.FromArgb(160, 140, 175);
        public static Color Ok        = Color.FromArgb(100, 190, 110);
        public static Color Warn      = Color.FromArgb(230, 190, 50);
        public static Color Err       = Color.FromArgb(240, 90, 100);
        public static Color Field     = Color.FromArgb(24, 16, 36);

        public static Font FTitle = new Font("Segoe UI Semibold", 23f, FontStyle.Bold);
        public static Font FSub   = new Font("Segoe UI", 9f);
        public static Font FName  = new Font("Segoe UI Semibold", 9.5f);
        public static Font FDesc  = new Font("Segoe UI", 8.2f);
        public static Font FBtn   = new Font("Segoe UI Semibold", 9.5f);
        public static Font FMono  = new Font("Consolas", 8.2f);
        public static Font FSmall = new Font("Segoe UI", 7.8f);
        public static Font FHead  = new Font("Segoe UI Semibold", 8.2f);

        public static void ScaleFonts(float s)
        {
            if (s < 0.5f) s = 1f;
            if (Math.Abs(s - 1f) < 0.01f) return;
            FTitle = new Font("Segoe UI Semibold", 23f * s, FontStyle.Bold);
            FSub   = new Font("Segoe UI", 9f * s);
            FName  = new Font("Segoe UI Semibold", 9.5f * s);
            FDesc  = new Font("Segoe UI", 8.2f * s);
            FBtn   = new Font("Segoe UI Semibold", 9.5f * s);
            FMono  = new Font("Consolas", 8.2f * s);
            FSmall = new Font("Segoe UI", 7.8f * s);
            FHead  = new Font("Segoe UI Semibold", 8.2f * s);
        }

        public static Color Lerp(Color a, Color b, float t)
        {
            t = Ease.Clamp01(t);
            return Color.FromArgb(
                (int)(a.A + (b.A - a.A) * t),
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            if (rad <= 0.5f) { p.AddRectangle(r); return p; }
            float d = rad * 2f;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    public class BufferedPanel : Panel
    {
        public BufferedPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
    }

    // Панель с плавной прокруткой колесом мыши и без мерцания при перестройке.
    public class SmoothScrollPanel : BufferedPanel
    {
        private readonly Timer _t;
        private int _target;

        public SmoothScrollPanel()
        {
            AutoScroll = true;
            _t = new Timer();
            _t.Interval = 15;
            _t.Tick += OnTick;
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int cur = -AutoScrollPosition.Y;
            int max = 0;
            try { max = Math.Max(0, VerticalScroll.Maximum - VerticalScroll.LargeChange + 1); } catch { }
            _target = cur - e.Delta;
            if (_target < 0) _target = 0;
            if (_target > max) _target = max;
            if (!_t.Enabled) _t.Start();
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            WheelHub.Target = this;
            base.OnMouseEnter(e);
        }

        private void OnTick(object sender, EventArgs e)
        {
            int cur = -AutoScrollPosition.Y;
            int max = 0;
            try { max = Math.Max(0, VerticalScroll.Maximum - VerticalScroll.LargeChange + 1); } catch { }
            if (_target > max) _target = max;
            int d = _target - cur;
            if (Math.Abs(d) <= 1)
            {
                try { AutoScrollPosition = new Point(0, Math.Max(0, _target)); } catch { }
                _t.Stop();
                return;
            }
            int step = (int)Math.Round(d * 0.24);
            if (step == 0) step = Math.Sign(d);
            try { AutoScrollPosition = new Point(0, Math.Max(0, cur + step)); } catch { }
        }

        public void ScrollToTop()
        {
            _target = 0;
            _t.Stop();
            try { AutoScrollPosition = new Point(0, 0); } catch { }
        }

        public void ScrollToValue(int v)
        {
            _target = Math.Max(0, v);
            _t.Stop();
            try { AutoScrollPosition = new Point(0, _target); } catch { }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _t != null) { try { _t.Stop(); _t.Dispose(); } catch { } }
            base.Dispose(disposing);
        }
    }

    // Заметная вертикальная полоса прокрутки со стрелками вверх/вниз.
    // Накладывается поверх штатной полосы целевой панели и работает
    // с её AutoScrollPosition, поэтому не ломает колесо и клавиатуру.
    public class ScrollStrip : Control
    {
        private readonly Timer _t;
        private Control _target;
        private bool _hoverUp, _hoverDown, _hoverThumb;
        private bool _dragging;
        private int _dragOffset;
        private int _arrowH;
        private bool _syncing;

        public Control Target
        {
            get { return _target; }
            set
            {
                _target = value;
                ScrollableControl sc = _target as ScrollableControl;
                if (sc != null)
                {
                    sc.Scroll += delegate { RequestSync(); };
                    sc.Resize += delegate { RequestSync(); };
                    sc.ClientSizeChanged += delegate { RequestSync(); };
                    sc.VisibleChanged += delegate { RequestSync(); };
                    sc.ControlAdded += delegate { RequestSync(); };
                    sc.ControlRemoved += delegate { RequestSync(); };
                }
                Visible = false;
                RequestSync();
            }
        }

        public ScrollStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            _arrowH = 16;
            try { Width = SystemInformation.VerticalScrollBarWidth; } catch { Width = 17; }
            // Таймер не тикает постоянно: он запускается только после
            // изменения прокрутки/размера и сразу останавливается.
            _t = new Timer();
            _t.Interval = 24;
            _t.Tick += delegate { _t.Stop(); Sync(); };
        }

        public void RequestSync()
        {
            if (IsDisposed || _t == null) return;
            if (!_t.Enabled) _t.Start();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _t != null) { try { _t.Stop(); _t.Dispose(); } catch { } }
            base.Dispose(disposing);
        }

        private ScrollableControl Sc { get { return _target as ScrollableControl; } }

        private int MaxValue
        {
            get
            {
                if (Sc == null) return 0;
                try { return Math.Max(0, Sc.VerticalScroll.Maximum - Sc.VerticalScroll.LargeChange + 1); }
                catch { return 0; }
            }
        }

        private int Value
        {
            get
            {
                if (Sc == null) return 0;
                try { return Math.Max(0, -Sc.AutoScrollPosition.Y); } catch { return 0; }
            }
        }

        private int ContentHeight
        {
            get
            {
                if (Sc == null) return 0;
                try { return Math.Max(1, Sc.VerticalScroll.Maximum); } catch { return 1; }
            }
        }

        private int ViewHeight
        {
            get
            {
                if (Sc == null) return 1;
                try { return Math.Max(1, Sc.ClientSize.Height); } catch { return 1; }
            }
        }

        public void Sync()
        {
            if (_syncing || Sc == null || Sc.IsDisposed || IsDisposed) return;
            _syncing = true;
            try
            {
                bool need = false;
                try { need = Sc.VerticalScroll.Visible && MaxValue > 0; } catch { }
                if (!need)
                {
                    if (Visible) Visible = false;
                    return;
                }

                int x, y, h;
                if (Parent == _target)
                {
                    x = Math.Max(0, Sc.ClientSize.Width - Width);
                    y = -Sc.AutoScrollPosition.Y;
                    h = Sc.ClientSize.Height;
                }
                else
                {
                    x = _target.Right - Width;
                    y = _target.Top;
                    h = _target.Height;
                }
                if (Bounds.X != x || Bounds.Y != y || Bounds.Height != h || Bounds.Width != Width)
                {
                    Bounds = new Rectangle(x, y, Width, h);
                }
                if (!Visible)
                {
                    Visible = true;
                    BringToFront();
                }
                Invalidate();
            }
            catch { }
            finally { _syncing = false; }
        }

        private int TrackTop { get { return _arrowH + 2; } }
        private int TrackBottom { get { return Height - _arrowH - 2; } }
        private int TrackHeight { get { return Math.Max(1, TrackBottom - TrackTop); } }

        private int ThumbHeight()
        {
            int h = (int)Math.Round((double)TrackHeight * Math.Min(1.0, (double)ViewHeight / ContentHeight));
            return Math.Max(24, Math.Min(TrackHeight, h));
        }

        private Rectangle ThumbRect()
        {
            int th = ThumbHeight();
            int room = TrackHeight - th;
            int max = MaxValue;
            int y = TrackTop;
            if (max > 0 && room > 0)
            {
                y += (int)Math.Round((double)room * Math.Min(1.0, (double)Value / max));
            }
            return new Rectangle(3, y, Math.Max(4, Width - 6), th);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int w = Width, h = Height;
            using (SolidBrush b = new SolidBrush(Theme.Field)) g.FillRectangle(b, 0, 0, w, h);
            DrawArrow(g, _hoverUp ? Theme.AccentLt : Theme.Muted, 0, true);
            DrawArrow(g, _hoverDown ? Theme.AccentLt : Theme.Muted, h - _arrowH, false);

            Color track = Theme.Lerp(Theme.Field, Theme.Bg, 0.55f);
            using (SolidBrush tb = new SolidBrush(track)) g.FillRectangle(tb, 3, TrackTop, Math.Max(1, w - 6), TrackHeight);

            Rectangle tr = ThumbRect();
            Color thumb = (_dragging || _hoverThumb) ? Theme.AccentLt : Theme.Accent;
            using (GraphicsPath p = RoundRect(tr, 5))
            using (SolidBrush sb = new SolidBrush(thumb)) g.FillPath(sb, p);
            using (Pen pen = new Pen(Theme.Lerp(Theme.Accent, Color.White, 0.3f), 1f))
            {
                if (tr.Width > 6) g.DrawLine(pen, tr.X + 3, tr.Y + 3, tr.Right - 4, tr.Y + 3);
            }
            using (Pen bp = new Pen(Theme.Lerp(Theme.BorderC, Theme.Bg, 0.35f), 1f))
            {
                g.DrawRectangle(bp, 0, 0, w - 1, h - 1);
            }
        }

        private void DrawArrow(Graphics g, Color c, int top, bool up)
        {
            int cx = Width / 2;
            int cy = top + _arrowH / 2;
            Point[] p = up
                ? new Point[] { new Point(cx, cy - 4), new Point(cx - 5, cy + 2), new Point(cx + 5, cy + 2) }
                : new Point[] { new Point(cx, cy + 4), new Point(cx - 5, cy - 2), new Point(cx + 5, cy - 2) };
            using (SolidBrush b = new SolidBrush(c)) g.FillPolygon(b, p);
        }

        private GraphicsPath RoundRect(Rectangle r, int rad)
        {
            GraphicsPath p = new GraphicsPath();
            int d = Math.Max(2, rad * 2);
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        private void ScrollTo(int v)
        {
            if (Sc == null) return;
            int max = MaxValue;
            if (v < 0) v = 0;
            if (v > max) v = max;
            SmoothScrollPanel smooth = Sc as SmoothScrollPanel;
            if (smooth != null) smooth.ScrollToValue(v);
            else { try { Sc.AutoScrollPosition = new Point(0, v); } catch { } }
            Invalidate();
        }

        private void PageTo(int dir)
        {
            int page = Math.Max(40, ViewHeight - 40);
            ScrollTo(Value + dir * page);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            if (e.Y < _arrowH) { PageTo(-1); return; }
            if (e.Y >= Height - _arrowH) { PageTo(1); return; }
            Rectangle tr = ThumbRect();
            if (tr.Contains(e.Location))
            {
                _dragging = true;
                _dragOffset = e.Y - tr.Y;
            }
            else
            {
                ScrollTo(Value + (e.Y < tr.Y ? -1 : 1) * Math.Max(40, ViewHeight - 40));
            }
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            _hoverUp = e.Y < _arrowH;
            _hoverDown = e.Y >= Height - _arrowH;
            _hoverThumb = ThumbRect().Contains(e.Location);
            if (_dragging)
            {
                int room = TrackHeight - ThumbHeight();
                int rel = e.Y - TrackTop - _dragOffset;
                if (rel < 0) rel = 0;
                if (rel > room) rel = room;
                int max = MaxValue;
                int v = (room <= 0 || max <= 0) ? 0 : (int)Math.Round((double)max * rel / room);
                ScrollTo(v);
            }
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _dragging = false;
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            _hoverUp = _hoverDown = _hoverThumb = false;
            _dragging = false;
            Invalidate();
        }
    }

    // Колесо мыши над навигацией/панелями тоже прокручивает контент.
    // Не перехватываем колесо у списков, полей ввода и самих прокручиваемых панелей.
    public static class WheelHub
    {
        public static SmoothScrollPanel Target;

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(POINT p);
        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        public static bool Route(Message m)
        {
            if (Target == null || Target.IsDisposed || !Target.IsHandleCreated) return false;
            Form host = Target.FindForm();
            if (host == null || Form.ActiveForm != host) return false;
            POINT p;
            if (!GetCursorPos(out p)) return false;
            Control c = Control.FromHandle(WindowFromPoint(p));

            // Курсор над нашей полосой — крутим её панель, а не контент.
            ScrollStrip strip = c as ScrollStrip;
            if (strip != null && strip.Target != null && strip.Target.IsHandleCreated)
            {
                SendMessage(strip.Target.Handle, m.Msg, m.WParam, m.LParam);
                return true;
            }

            for (Control x = c; x != null; x = x.Parent)
            {
                if (x is TextBoxBase || x is ListBox || x is ComboBox) return false;

                // Меню разделов и другие AutoScroll-панели листаются своим колесом.
                ScrollableControl sc = x as ScrollableControl;
                if (sc != null && sc.AutoScroll && sc != Target)
                {
                    bool canScroll = false;
                    try { canScroll = sc.VerticalScroll.Visible && sc.VerticalScroll.Maximum > sc.VerticalScroll.LargeChange; }
                    catch { }
                    if (canScroll)
                    {
                        SendMessage(sc.Handle, m.Msg, m.WParam, m.LParam);
                        return true;
                    }
                }
                if (x is SmoothScrollPanel) return false;
            }
            SendMessage(Target.Handle, m.Msg, m.WParam, m.LParam);
            return true;
        }
    }

    public class WheelRouter : IMessageFilter
    {
        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != 0x020A) return false;
            try { return WheelHub.Route(m); } catch { return false; }
        }
    }

    // Плавное появление раздела: снимок новой страницы проявляется
    // на фоне темы за несколько кадров. В отличие от прозрачной вуали,
    // снимок не может скрыть содержимое под собой.
    public class FadeVeil : Control, IAnim
    {
        private Bitmap _snap;
        private int _alpha;
        private int _step;

        public FadeVeil()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
            Visible = false;
            Enabled = false;
            TabStop = false;
        }

        public void Begin(Bitmap snap, int frames)
        {
            Cancel();
            if (snap == null) return;
            _snap = snap;
            _alpha = 0;
            _step = Math.Max(12, 255 / Math.Max(1, frames));
            Visible = true;
            try { BringToFront(); } catch { }
            Anim.Add(this);
            Invalidate();
        }

        public void Cancel()
        {
            try { Anim.Remove(this); } catch { }
            if (_snap != null) { try { _snap.Dispose(); } catch { } _snap = null; }
            _alpha = 0;
            Visible = false;
        }

        public bool Tick()
        {
            if (_snap == null) { Visible = false; return false; }
            _alpha += _step;
            if (_alpha >= 255)
            {
                _alpha = 255;
                Invalidate();
                Bitmap b = _snap;
                _snap = null;
                Visible = false;
                if (b != null) { try { b.Dispose(); } catch { } }
                return false;
            }
            Invalidate();
            return true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Theme.Bg);
            if (_snap == null || _alpha <= 0) return;
            ImageAttributes ia = new ImageAttributes();
            try
            {
                ColorMatrix cm = new ColorMatrix();
                cm.Matrix33 = _alpha / 255f;
                ia.SetColorMatrix(cm, ColorMatrixFlag.Default, ColorAdjustType.Bitmap);
                e.Graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
                e.Graphics.DrawImage(_snap, new Rectangle(0, 0, Width, Height),
                    0, 0, _snap.Width, _snap.Height, GraphicsUnit.Pixel, ia);
            }
            finally { ia.Dispose(); }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _snap != null) { try { _snap.Dispose(); } catch { } _snap = null; }
            base.Dispose(disposing);
        }
    }

    public class HeaderPanel : Panel, IAnim
    {
        private float _phase = 0.15f;
        private int _skip;
        private int _idle;
        public HeaderPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.PanelBg;
            Anim.Add(this);
        }
        public void Wake()
        {
            _idle = 0;
            Anim.Add(this);
        }
        public bool Tick()
        {
            // Блик движется плавно, но перерисовывается ~20 раз в секунду,
            // а не 66: шапка не греет CPU и не мешает плавности прокрутки.
            _phase += 0.0114f;
            if (_phase > 1.35f) _phase = -0.25f;
            _skip++;
            // После ~20 секунд без действий анимация засыпает и
            // просыпается от навигации, смены темы или наведения.
            _idle++;
            if (_idle > 1200) return false;
            if (_skip < 3) return true;
            _skip = 0;
            Invalidate();
            return true;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rc = new Rectangle(0, 0, Width, Height);
            using (LinearGradientBrush b = new LinearGradientBrush(rc, Theme.PanelBg, Theme.Bg, LinearGradientMode.Vertical))
                g.FillRectangle(b, rc);

            float sx = _phase * (Width + 620f) - 310f;
            Rectangle sheen = new Rectangle((int)sx, 0, 190, Height);
            using (LinearGradientBrush b = new LinearGradientBrush(sheen, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend cb = new ColorBlend(3);
                cb.Colors = new Color[] { Color.FromArgb(0, Theme.Accent), Color.FromArgb(130, Theme.Secondary), Color.FromArgb(0, Theme.Accent) };
                cb.Positions = new float[] { 0f, 0.5f, 1f };
                b.InterpolationColors = cb;
                g.FillRectangle(b, sheen);
            }

            using (SolidBrush b = new SolidBrush(Theme.Accent)) g.FillRectangle(b, 0, Height - 2, Width, 2);
            float gx = ((_phase * 1.7f) % 1f) * Width;
            Rectangle glow = new Rectangle((int)gx - 90, Height - 3, 180, 5);
            using (LinearGradientBrush b = new LinearGradientBrush(glow, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend cb = new ColorBlend(3);
                cb.Colors = new Color[] { Color.FromArgb(0, Theme.Accent), Color.FromArgb(160, Theme.Secondary), Color.FromArgb(0, Theme.Accent) };
                cb.Positions = new float[] { 0f, 0.5f, 1f };
                b.InterpolationColors = cb;
                g.FillRectangle(b, glow);
            }
            // Пользовательские Paint-обработчики (текст шапки) вызываются
            // базовым OnPaint; без этого события Paint не срабатывает.
            base.OnPaint(e);
        }
    }

    public class Card : Panel, IAnim
    {
        private bool _on, _hover;
        private float _p, _ha;
        public string Title = "";
        public string Sub = "";
        public bool Risk;
        public event EventHandler Toggled;

        public bool On
        {
            get { return _on; }
            set
            {
                if (_on == value) return;
                _on = value;
                Anim.Add(this);
                Invalidate();
                EventHandler h = Toggled;
                if (h != null) h(this, EventArgs.Empty);
            }
        }

        public Card()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Bg;
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e)
        { _hover = true; Anim.Add(this); Invalidate(); base.OnMouseEnter(e); }

        protected override void OnMouseLeave(EventArgs e)
        {
            _hover = ClientRectangle.Contains(PointToClient(Cursor.Position));
            Anim.Add(this); Invalidate(); base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left) On = !On;
        }

        public bool Tick()
        {
            float tp = _on ? 1f : 0f;
            float th = _hover ? 1f : 0f;
            _p = Ease.Approach(_p, tp, 0.22f);
            _ha = Ease.Approach(_ha, th, 0.25f);
            Invalidate();
            return !(Ease.Done(_p, tp) && Ease.Done(_ha, th));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = Theme.Lerp(Theme.CardBg, Theme.CardHover, _ha);
            Color line = Theme.Lerp(Theme.BorderC, Color.FromArgb(64, 255, 255, 255), _ha);
            if (_p > 0.01f) line = Theme.Lerp(line, Color.FromArgb(120, Theme.Accent), _p);
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                    Theme.Lerp(fill, Color.White, 0.035f), fill, LinearGradientMode.Vertical))
                    g.FillPath(b, p);
                using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p);
                // Тонкий блик по верхней кромке — карточка выглядит объёмнее.
                using (Pen hi = new Pen(Color.FromArgb(26, 255, 255, 255), 1f))
                    g.DrawLine(hi, 10, 1.5f, Math.Max(11, Width - 10), 1.5f);
            }
            if (_p > 0.02f)
            {
                int h = Height - 26;
                if (h < 8) h = 8;
                using (SolidBrush b = new SolidBrush(Color.FromArgb((int)(230 * _p), Theme.Accent)))
                    g.FillRectangle(b, 0, (Height - h) / 2, 3, h);
            }

            int tw = Width - 100;
            if (tw < 60) tw = 60;
            Color tc = Risk ? Theme.Warn : Theme.TextC;
            TextRenderer.DrawText(g, Title, Theme.FName, new Rectangle(16, 11, tw, 20), tc,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            int dh = Height - 40;
            if (dh < 10) dh = 10;
            TextRenderer.DrawText(g, Sub, Theme.FDesc, new Rectangle(16, 32, tw, dh), Theme.Muted,
                TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            float tww = 42f, thh = 22f;
            if (Width > 130)
            {
                float tx = Width - tww - 16f;
                float ty = (Height - thh) / 2f;
                using (GraphicsPath p = Theme.Round(new RectangleF(tx, ty, tww, thh), thh / 2f))
                using (SolidBrush b = new SolidBrush(Theme.Lerp(Color.FromArgb(44, 51, 65), Theme.Accent, _p)))
                    g.FillPath(b, p);
                float d = thh - 7f;
                float kx = tx + 3.5f + (tww - d - 7f) * _p;
                using (SolidBrush b = new SolidBrush(Theme.Lerp(Color.FromArgb(140, 151, 166), Color.White, _p)))
                    g.FillEllipse(b, kx, ty + 3.5f, d, d);
            }
        }
    }

    public class FlatButton : Control, IAnim
    {
        public enum Kind { Primary, Ghost }
        public Kind Style = Kind.Primary;
        private bool _hover, _down;
        private float _ha;
        private float _rx, _ry, _rr, _ra;

        public FlatButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
            Cursor = Cursors.Hand;
            Font = Theme.FBtn;
            ForeColor = Theme.TextC;
            BackColor = Color.Transparent;
            TabStop = true;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; _down = false; Anim.Add(this); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            _down = true; _rx = e.X; _ry = e.Y; _rr = 4f; _ra = 0.30f;
            Anim.Add(this); base.OnMouseDown(e);
        }
        protected override void OnMouseUp(MouseEventArgs e) { _down = false; Anim.Add(this); base.OnMouseUp(e); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { e.Handled = true; OnClick(EventArgs.Empty); }
            base.OnKeyDown(e);
        }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        public bool Tick()
        {
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.25f);
            bool ripple = false;
            if (_ra > 0.01f)
            {
                _rr += Math.Max(6f, Width / 18f);
                _ra -= 0.045f;
                if (_ra < 0f) _ra = 0f;
                ripple = true;
            }
            Invalidate();
            return !Ease.Done(_ha, _hover ? 1f : 0f) || ripple;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill, line = Color.Empty, text = ForeColor;
            if (Style == Kind.Primary)
            {
                fill = !Enabled ? Color.FromArgb(70, Theme.Accent)
                     : _down ? Theme.Lerp(Theme.Accent, Color.Black, 0.25f)
                     : Theme.Lerp(Theme.Accent, Theme.AccentLt, _ha);
                text = Enabled ? Color.White : Color.FromArgb(150, 150, 150);
            }
            else
            {
                fill = _down ? Theme.Lerp(Theme.CardBg, Color.Black, 0.22f)
                     : Theme.Lerp(Theme.PanelBg, Theme.CardBg, _ha);
                line = _hover ? Theme.Lerp(Theme.BorderC, Theme.AccentLt, 0.45f) : Theme.BorderC;
                text = Enabled ? Theme.TextC : Color.FromArgb(110, 118, 130);
            }
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                if (line != Color.Empty) { using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p); }
                if (_ra > 0.01f)
                {
                    GraphicsState st = g.Save();
                    g.SetClip(p);
                    using (SolidBrush rb = new SolidBrush(Color.FromArgb((int)(255 * _ra), 255, 255, 255)))
                        g.FillEllipse(rb, _rx - _rr, _ry - _rr, _rr * 2f, _rr * 2f);
                    g.Restore(st);
                }
            }
            if (Focused && Enabled)
            {
                using (Pen pen = new Pen(Color.FromArgb(90, 255, 255, 255), 1f))
                using (GraphicsPath p = Theme.Round(new RectangleF(3f, 3f, Width - 7f, Height - 7f), 7f))
                    g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    public class NavButton : Control, IAnim
    {
        private bool _hover, _sel;
        private float _sa, _ha;
        public string Sub = "";

        public bool Selected { get { return _sel; } set { _sel = value; Anim.Add(this); Invalidate(); } }

        public NavButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            Cursor = Cursors.Hand;
            BackColor = Color.Transparent;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Anim.Add(this); base.OnMouseLeave(e); }

        public bool Tick()
        {
            _sa = Ease.Approach(_sa, _sel ? 1f : 0f, 0.24f);
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.25f);
            Invalidate();
            return !(Ease.Done(_sa, _sel ? 1f : 0f) && Ease.Done(_ha, _hover ? 1f : 0f));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2.5f, Height - 1.5f);
            float a = Math.Max(_sa, _ha * 0.55f);
            if (a > 0.02f)
            {
                Color navFill = Theme.Lerp(Theme.Bg, Theme.CardHover, _sel ? 0.85f : 0.45f);
                using (GraphicsPath p = Theme.Round(r, 8f))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(_sel ? 165 : 70, navFill)))
                    g.FillPath(b, p);
            }
            if (_sa > 0.02f)
            {
                int h = (int)(18 * Ease.OutBack(_sa));
                if (h > Height - 8) h = Height - 8;
                using (SolidBrush b = new SolidBrush(Theme.Accent))
                    g.FillRectangle(b, 0, (Height - h) / 2, 3, h);
            }
            Color c = Theme.Lerp(Theme.Muted, Theme.TextC, Math.Max(_sa, _ha * 0.8f));
            using (Font f = new Font("Segoe UI Semibold", 9.2f))
                TextRenderer.DrawText(g, Text, f, new Rectangle(14, 8, Width - 22, 18), c,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            if (!string.IsNullOrEmpty(Sub))
            {
                Color sc = Theme.Lerp(Theme.Muted, Theme.TextC, _sa * 0.7f);
                using (Font f = new Font("Segoe UI", 7.4f))
                    TextRenderer.DrawText(g, Sub, f, new Rectangle(14, 26, Width - 22, 14), sc,
                        TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
        }
    }

    public class ThemeTile : Control, IAnim
    {
        public string Title = "";
        public string Sub = "";
        public Color ColorA = Theme.Accent;
        public Color ColorB = Theme.AccentLt;
        public Color ColorC = Theme.Secondary;
        private bool _sel, _hover;
        private float _sa, _ha, _phase;

        public bool Selected
        {
            get { return _sel; }
            set { _sel = value; Anim.Add(this); Invalidate(); }
        }

        public ThemeTile()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Anim.Add(this); base.OnMouseLeave(e); }

        public bool Tick()
        {
            _sa = Ease.Approach(_sa, _sel ? 1f : 0f, 0.2f);
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.22f);
            if (_sel || _hover) { _phase += 0.022f; if (_phase > 1f) _phase -= 1f; }
            Invalidate();
            return !(Ease.Done(_sa, _sel ? 1f : 0f) && Ease.Done(_ha, _hover ? 1f : 0f));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (GraphicsPath p = Theme.Round(r, 10f))
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                    ColorA, ColorB, LinearGradientMode.ForwardDiagonal))
                    g.FillPath(b, p);

                using (LinearGradientBrush dark = new LinearGradientBrush(
                    new Rectangle(0, Math.Max(0, Height - 46), Math.Max(2, Width), 46),
                    Color.FromArgb(0, 0, 0, 0), Color.FromArgb(150, 0, 0, 0), LinearGradientMode.Vertical))
                {
                    GraphicsState st = g.Save();
                    g.SetClip(p);
                    g.FillRectangle(dark, 0, Height - 46, Width, 46);
                    g.Restore(st);
                }

                if (_ha > 0.02f || _sel)
                {
                    GraphicsState st = g.Save();
                    g.SetClip(p);
                    float sx = (float)(_phase * (Width + 160.0)) - 80f;
                    using (LinearGradientBrush sheen = new LinearGradientBrush(
                        new Rectangle((int)sx, 0, 70, Math.Max(2, Height)),
                        Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255),
                        LinearGradientMode.Horizontal))
                    {
                        ColorBlend cb = new ColorBlend(3);
                        cb.Colors = new Color[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(45, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) };
                        cb.Positions = new float[] { 0f, 0.5f, 1f };
                        sheen.InterpolationColors = cb;
                        g.FillRectangle(sheen, new Rectangle((int)sx, 0, 70, Height));
                    }
                    g.Restore(st);
                }

                Color border = _sel ? Color.White : (_hover ? Color.FromArgb(200, 255, 255, 255) : Color.FromArgb(90, 255, 255, 255));
                using (Pen pen = new Pen(border, _sel ? 2f : 1f)) g.DrawPath(pen, p);
            }

            TextRenderer.DrawText(g, Title, Theme.FName, new Rectangle(14, Height - 36, Width - 70, 18), Color.White,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, Sub, Theme.FSmall, new Rectangle(14, Height - 19, Width - 20, 14), Color.FromArgb(220, 240, 235, 255),
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            int cy = 14;
            using (SolidBrush b = new SolidBrush(ColorC)) g.FillEllipse(b, Width - 30, cy, 9, 9);
            using (SolidBrush b = new SolidBrush(Color.FromArgb(150, 255, 255, 255))) g.FillEllipse(b, Width - 18, cy + 3, 5, 5);

            if (_sel)
            {
                using (SolidBrush b = new SolidBrush(Color.FromArgb(230, 255, 255, 255)))
                    g.FillEllipse(b, Width - 34, 10, 20, 20);
                TextRenderer.DrawText(g, "✓", Theme.FSmall, new Rectangle(Width - 34, 9, 20, 20), Color.FromArgb(35, 15, 55),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            }
        }
    }

    public class HealthRow : Control, IAnim
    {
        public string Title = "";
        public string Detail = "";
        public string ActionText = "";
        private string _status = "info";
        private bool _hover;
        private float _ha, _phase;

        public string Status
        {
            get { return _status; }
            set { _status = value ?? "info"; Anim.Add(this); Invalidate(); }
        }

        public event EventHandler ActionClicked;

        public HealthRow()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Cursor = Cursors.Default; Anim.Add(this); base.OnMouseLeave(e); }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Cursor = (e.X >= Width - 150 && !string.IsNullOrEmpty(ActionText)) ? Cursors.Hand : Cursors.Default;
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left && e.X >= Width - 150 && !string.IsNullOrEmpty(ActionText))
            {
                EventHandler h = ActionClicked;
                if (h != null) h(this, EventArgs.Empty);
            }
        }

        public bool Tick()
        {
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.22f);
            bool pulse = (_status == "warn" || _status == "err");
            if (pulse) { _phase += 0.045f; if (_phase > 1f) _phase -= 1f; }
            Invalidate();
            return pulse || !Ease.Done(_ha, _hover ? 1f : 0f);
        }

        private Color StatusColor()
        {
            if (_status == "ok") return Theme.Ok;
            if (_status == "warn") return Theme.Warn;
            if (_status == "err") return Theme.Err;
            return Theme.AccentLt;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = Theme.Lerp(Theme.CardBg, Theme.CardHover, _ha);
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.Lerp(Theme.BorderC, Color.FromArgb(110, 255, 255, 255), _ha), 1f))
                    g.DrawPath(pen, p);
            }
            Color sc = StatusColor();
            float pulse = 0.35f + 0.25f * (float)Math.Sin(_phase * Math.PI * 2.0);
            if (_status == "warn" || _status == "err")
                using (SolidBrush glow = new SolidBrush(Color.FromArgb((int)(50 * pulse), sc.R, sc.G, sc.B)))
                    g.FillEllipse(glow, 13, Height / 2 - 7, 14, 14);
            using (SolidBrush dot = new SolidBrush(sc))
                g.FillEllipse(dot, 17, Height / 2 - 3, 6, 6);
            using (SolidBrush bar = new SolidBrush(Color.FromArgb(110, sc)))
                g.FillRectangle(bar, 0, 12, 3, Height - 24);

            int actionW = string.IsNullOrEmpty(ActionText) ? 0 : 132;
            int tw = Width - 42 - actionW;
            if (tw < 80) tw = 80;
            TextRenderer.DrawText(g, Title, Theme.FName, new Rectangle(30, 7, tw, 19), Theme.TextC,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, Detail, Theme.FSmall, new Rectangle(30, 26, tw, Height - 29), Theme.Muted,
                TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            if (actionW > 0 && Width > 220)
            {
                int bw = 118, bh = 26;
                int bx = Width - bw - 14;
                int by = (Height - bh) / 2;
                using (GraphicsPath p = Theme.Round(new RectangleF(bx, by, bw, bh), 8f))
                {
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(30, sc.R, sc.G, sc.B))) g.FillPath(b, p);
                    using (Pen pen = new Pen(Color.FromArgb(120, sc.R, sc.G, sc.B), 1f)) g.DrawPath(pen, p);
                }
                TextRenderer.DrawText(g, ActionText, Theme.FSmall, new Rectangle(bx, by, bw, bh), sc,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
        }
    }

    public class ProgressStrip : Control, IAnim
    {        private double _v, _shown;
        private float _phase;
        private int _skip;
        public bool Shimmer = true;

        public double Value
        {
            get { return _v; }
            set { _v = Math.Max(0, Math.Min(100, value)); Anim.Add(this); }
        }

        public ProgressStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public bool Tick()
        {
            _shown = _shown + (_v - _shown) * 0.18;
            bool moving = Math.Abs(_v - _shown) > 0.05;
            bool shim = Shimmer && _shown > 0.5 && _shown < 99.5;
            if (moving)
            {
                _skip = 0;
                if (shim) { _phase += 0.025f; if (_phase > 1f) _phase -= 1f; }
                Invalidate();
                return true;
            }
            // Блик на неподвижной полосе перерисовывается реже — экономия CPU.
            if (shim)
            {
                _skip++;
                if (_skip >= 3)
                {
                    _skip = 0;
                    _phase += 0.075f;
                    if (_phase > 1f) _phase -= 1f;
                    Invalidate();
                }
                return true;
            }
            return false;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0, 0, Width, Height);
            using (GraphicsPath p = Theme.Round(r, Height / 2f))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(30, 36, 46)))
                g.FillPath(b, p);

            double w = Width * (_shown / 100.0);
            if (w >= 2)
            {
                RectangleF rf = new RectangleF(0, 0, (float)w, Height);
                using (GraphicsPath p = Theme.Round(rf, Height / 2f))
                {
                    using (LinearGradientBrush b = new LinearGradientBrush(
                        new Rectangle(0, 0, Math.Max(2, (int)w), Math.Max(2, Height)),
                        Theme.Accent, Theme.AccentLt, LinearGradientMode.Horizontal))
                        g.FillPath(b, p);
                    if (Shimmer && w > 24)
                    {
                        GraphicsState st = g.Save();
                        g.SetClip(p);
                        float sx = (float)(_phase * (w + 90.0)) - 45f;
                        using (LinearGradientBrush b = new LinearGradientBrush(
                            new Rectangle((int)sx, 0, 60, Math.Max(2, Height)),
                            Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255),
                            LinearGradientMode.Horizontal))
                        {
                            ColorBlend cb = new ColorBlend(3);
                            cb.Colors = new Color[] { Color.FromArgb(120, 255, 100, 160), Color.FromArgb(180, 160, 60, 240), Color.FromArgb(120, 255, 100, 160) };
                            cb.Positions = new float[] { 0f, 0.5f, 1f };
                            b.InterpolationColors = cb;
                            g.FillRectangle(b, new Rectangle((int)sx, 0, 60, Height));
                        }
                        g.Restore(st);
                    }
                }
            }
        }
    }

    public class Spinner : Control, IAnim
    {
        private float _angle;
        private bool _active;

        public bool Active
        {
            get { return _active; }
            set { _active = value; if (value) Anim.Add(this); Invalidate(); }
        }

        public Spinner()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public bool Tick()
        {
            if (!_active) return false;
            _angle += 11f;
            if (_angle > 360f) _angle -= 360f;
            Invalidate();
            return true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int d = Math.Min(Width, Height) - 4;
            if (d < 6 || !_active) return;
            RectangleF r = new RectangleF(2, 2, d, d);
            using (Pen bg = new Pen(Color.FromArgb(40, 255, 255, 255), 2.4f))
                g.DrawEllipse(bg, r);
            using (Pen pen = new Pen(Theme.AccentLt, 2.4f))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                g.DrawArc(pen, r, _angle, 100f);
            }
        }
    }

    // Компактная карточка-показатель для панели «ОБЗОР».
    public class StatCard : Control, IAnim
    {
        public string Label = "";
        public string Value = "";
        public string Hint = "";
        public Color AccentC = Theme.Accent;
        private bool _hover;
        private float _ha;
        private float _glow;

        public StatCard()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        public void SetValue(string v)
        {
            if (Value == v) return;
            Value = v == null ? "" : v;
            _glow = 1f;
            Anim.Add(this);
            Invalidate();
        }

        public void SetHint(string v)
        {
            string n = v == null ? "" : v;
            if (Hint == n) return;
            Hint = n;
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Anim.Add(this); Invalidate(); base.OnMouseLeave(e); }

        public bool Tick()
        {
            float th = _hover ? 1f : 0f;
            _ha = Ease.Approach(_ha, th, 0.22f);
            _glow = Ease.Approach(_glow, 0f, 0.06f);
            Invalidate();
            return !(Ease.Done(_ha, th) && _glow < 0.01f);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = Theme.Lerp(Theme.CardBg, Theme.CardHover, _ha);
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                    fill, Theme.PanelBg, LinearGradientMode.Vertical))
                    g.FillPath(b, p);
                Color line = Theme.Lerp(Theme.BorderC, Color.FromArgb(90, AccentC), Math.Max(_ha, _glow * 0.7f));
                using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p);
            }
            using (SolidBrush b = new SolidBrush(AccentC))
                g.FillRectangle(b, 0, 12, 3, Math.Max(6, Height - 24));

            TextRenderer.DrawText(g, Label, Theme.FHead, new Rectangle(14, 9, Width - 22, 16), Theme.Muted,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            using (Font fv = new Font("Segoe UI Semibold", 14f, FontStyle.Bold))
                TextRenderer.DrawText(g, Value, fv, new Rectangle(14, 24, Width - 22, Height - 40), Theme.TextC,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            if (!string.IsNullOrEmpty(Hint))
                TextRenderer.DrawText(g, Hint, Theme.FSmall, new Rectangle(14, Height - 20, Width - 22, 15), Theme.Muted,
                    TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    // Кольцевой индикатор оценки оптимизации: дуга, градиент, бегущий блик.
    public class RingGauge : Control, IAnim
    {
        private double _v, _shown;
        private float _phase;
        private string _caption = "";
        private string _sub = "";
        private int _idle;
        private int _skip;

        public double Value
        {
            get { return _v; }
            set
            {
                double nv = Math.Max(0, Math.Min(100, value));
                if (Math.Abs(nv - _v) < 0.001) return;
                _v = nv;
                _idle = 0;
                Anim.Add(this);
            }
        }

        public string Caption
        {
            get { return _caption; }
            set { _caption = value == null ? "" : value; Invalidate(); }
        }

        public string Sub
        {
            get { return _sub; }
            set { _sub = value == null ? "" : value; Invalidate(); }
        }

        public RingGauge()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _phase = 0.2f;
        }

        public bool Tick()
        {
            _shown = _shown + (_v - _shown) * 0.12;
            bool settling = Math.Abs(_v - _shown) > 0.05;
            if (settling)
            {
                _idle = 0;
                _skip = 0;
                _phase += 0.012f;
                if (_phase > 1f) _phase -= 1f;
                Invalidate();
                return true;
            }
            // После остановки блик живёт ещё ~1.5 секунды и плавно замирает.
            // Постоянный таймер не крутится вхолостую: интерфейс остаётся лёгким.
            if (_idle < 90)
            {
                _idle++;
                _skip++;
                if (_skip >= 4)
                {
                    _skip = 0;
                    _phase += 0.048f;
                    if (_phase > 1f) _phase -= 1f;
                    Invalidate();
                }
                return true;
            }
            return false;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int pad = 12;
            int side = Math.Min(Width, Height) - pad * 2;
            if (side < 20) return;
            RectangleF r = new RectangleF((Width - side) / 2f, (Height - side) / 2f, side, side);
            float th = Math.Max(6f, side * 0.075f);

            using (Pen track = new Pen(Color.FromArgb(36, Theme.BorderC), th))
            {
                track.StartCap = LineCap.Round;
                track.EndCap = LineCap.Round;
                g.DrawArc(track, r, 135f, 270f);
            }

            float sweep = (float)(270.0 * (_shown / 100.0));
            if (sweep > 0.4f)
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    Rectangle.Round(r), Theme.Accent, Theme.Secondary, 45f))
                using (Pen arc = new Pen(b, th))
                {
                    arc.StartCap = LineCap.Round;
                    arc.EndCap = LineCap.Round;
                    g.DrawArc(arc, r, 135f, sweep);
                }

                // Бегущий блик по дуге.
                if (_shown > 4 && _shown < 99.9)
                {
                    float a = 135f + sweep * _phase;
                    double rad = a * Math.PI / 180.0;
                    float cx = r.X + r.Width / 2f + (float)Math.Cos(rad) * (side / 2f);
                    float cy = r.Y + r.Height / 2f + (float)Math.Sin(rad) * (side / 2f);
                    float d = th * 0.55f;
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(210, Color.White)))
                        g.FillEllipse(b, cx - d / 2f, cy - d / 2f, d, d);
                }
            }

            string big = ((int)Math.Round(_shown)).ToString();
            using (Font fBig = new Font("Segoe UI Semibold", Math.Max(15f, side * 0.23f), FontStyle.Bold))
            using (Font fPct = new Font("Segoe UI", Math.Max(8f, side * 0.075f)))
            {
                Size bs = TextRenderer.MeasureText(big, fBig);
                Rectangle br = new Rectangle(0, (Height / 2) - (int)(bs.Height * 0.78), Width, bs.Height);
                TextRenderer.DrawText(g, big, fBig, br, Theme.TextC,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                Rectangle pr = new Rectangle((Width + bs.Width / 2) / 2 + 1, br.Y + (int)(bs.Height * 0.30), Width, (int)(bs.Height * 0.55));
                TextRenderer.DrawText(g, "%", fPct, pr, Theme.Muted,
                    TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPrefix);
            }
            if (!string.IsNullOrEmpty(_caption))
            {
                Rectangle cr = new Rectangle(0, (Height / 2) + (int)(side * 0.11), Width, 20);
                TextRenderer.DrawText(g, _caption, Theme.FHead, cr, Theme.TextC,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
            }
            if (!string.IsNullOrEmpty(_sub))
            {
                Rectangle sr = new Rectangle(0, (Height / 2) + (int)(side * 0.11) + 19, Width, 18);
                TextRenderer.DrawText(g, _sub, Theme.FSmall, sr, Theme.Muted,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
            }
        }
    }

    // Живой график нагрузки: заполненная область, линия и точка на конце.
    public class Sparkline : Control, IAnim
    {
        private readonly List<float> _pts = new List<float>();
        private readonly int _cap;
        private float _phase;
        private Color _line;
        private int _pulse;

        public Sparkline() : this(60) { }

        public Sparkline(int capacity)
        {
            _cap = Math.Max(4, capacity);
            _line = Theme.AccentLt;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public Color LineColor
        {
            get { return _line; }
            set { _line = value; Invalidate(); }
        }

        public void Push(double value)
        {
            float v = (float)Math.Max(0, Math.Min(100, value));
            _pts.Add(v);
            while (_pts.Count > _cap) _pts.RemoveAt(0);
            _pulse = 24;
            Anim.Add(this);
            Invalidate();
        }

        public void Reset()
        {
            _pts.Clear();
            Invalidate();
        }

        public int Count { get { return _pts.Count; } }

        public bool Tick()
        {
            if (_pts.Count < 2) return false;
            // Пульс точки запускается только после нового замера (раз в 2.5 с),
            // а не крутится 66 кадров/с всё время, пока открыт «ОБЗОР».
            if (_pulse <= 0) return false;
            _pulse--;
            _phase += 0.05f;
            if (_phase > 1f) _phase -= 1f;
            Invalidate();
            return _pulse > 0;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int n = _pts.Count;
            if (n < 2 || Width < 8 || Height < 8) return;

            // Мягкая сетка.
            using (Pen grid = new Pen(Color.FromArgb(22, Theme.BorderC), 1f))
            {
                for (int i = 1; i < 4; i++)
                {
                    int yy = Height * i / 4;
                    g.DrawLine(grid, 0, yy, Width, yy);
                }
            }

            PointF[] pts = new PointF[n];
            float stepX = Width / (float)(n - 1);
            for (int i = 0; i < n; i++)
            {
                float y = Height - 2f - (_pts[i] / 100f) * (Height - 4f);
                pts[i] = new PointF(i * stepX, y);
            }

            GraphicsPath area = new GraphicsPath();
            area.AddLine(0, Height, (int)pts[0].X, (int)pts[0].Y);
            area.AddLines(pts);
            area.AddLine((int)pts[n - 1].X, (int)pts[n - 1].Y, Width, Height);
            area.AddLine(Width, Height, 0, Height);
            area.CloseFigure();
            using (LinearGradientBrush b = new LinearGradientBrush(
                new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                Color.FromArgb(110, _line), Color.FromArgb(0, _line), 90f))
                g.FillPath(b, area);
            area.Dispose();

            using (Pen pen = new Pen(_line, 1.8f))
            {
                pen.LineJoin = LineJoin.Round;
                g.DrawLines(pen, pts);
            }

            PointF last = pts[n - 1];
            float r = 3.0f + (float)(Math.Sin(_phase * Math.PI * 2) * 1.2);
            using (SolidBrush halo = new SolidBrush(Color.FromArgb(90, _line)))
                g.FillEllipse(halo, last.X - r * 2, last.Y - r * 2, r * 4, r * 4);
            using (SolidBrush dot = new SolidBrush(_line))
                g.FillEllipse(dot, last.X - r, last.Y - r, r * 2, r * 2);
        }
    }

    public class SlideTween : IAnim
    {
        private readonly Control _c;
        private readonly float _from, _to, _delay, _dur;
        private float _t;

        public SlideTween(Control c, int fromTop, int toTop, int delayMs, int durMs)
        {
            _c = c;
            _from = fromTop;
            _to = toTop;
            _delay = Math.Max(0, delayMs);
            _dur = Math.Max(1, durMs);
            Anim.Add(this);
        }

        public bool Tick()
        {
            _t += 16f;
            if (_t < _delay) return true;
            float p = Ease.Clamp01((_t - _delay) / _dur);
            float e = Ease.OutCubic(p);
            if (_c != null && !_c.IsDisposed)
            {
                int top = (int)Math.Round(_from + (_to - _from) * e);
                if (_c.Top != top) _c.Top = top;
            }
            return p < 1f;
        }
    }

    public static class Native
    {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        public static extern int SetWindowTheme(IntPtr hwnd, string sub, string sub2);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        private const int WM_SETREDRAW = 0x000B;

        // Пакетная перерисовка: строим панель без промежуточных миганий.
        public static void SetRedraw(Control c, bool enabled)
        {
            try { SendMessage(c.Handle, WM_SETREDRAW, enabled ? (IntPtr)1 : IntPtr.Zero, IntPtr.Zero); } catch { }
        }

        public static void DarkTitle(Form f)
        {
            try
            {
                int v = 1;
                DwmSetWindowAttribute(f.Handle, 20, ref v, 4);
                DwmSetWindowAttribute(f.Handle, 19, ref v, 4);
                // Windows 11: скруглённые углы окна (на Windows 10 вызов игнорируется).
                int corner = 2;
                DwmSetWindowAttribute(f.Handle, 33, ref corner, 4);
            }
            catch { }
        }
        public static void DarkScroll(Control c)
        {
            try { SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { }
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public class MEMORYSTATUSEX
        {
            public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

        // Быстрый % загрузки ОЗУ без WMI и без блокировки интерфейса.
        public static int MemLoad()
        {
            try
            {
                MEMORYSTATUSEX m = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(m)) return (int)m.dwMemoryLoad;
            }
            catch { }
            return -1;
        }

        public static long MemTotalMb()
        {
            try
            {
                MEMORYSTATUSEX m = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(m)) return (long)(m.ullTotalPhys / 1048576UL);
            }
            catch { }
            return 0;
        }

        public static long MemFreeMb()
        {
            try
            {
                MEMORYSTATUSEX m = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(m)) return (long)(m.ullAvailPhys / 1048576UL);
            }
            catch { }
            return 0;
        }

        // Реальное разрешение системного таймера 1 мс на время работы программы.
        [DllImport("winmm.dll")]
        private static extern uint timeBeginPeriod(uint uPeriod);
        [DllImport("winmm.dll")]
        private static extern uint timeEndPeriod(uint uPeriod);

        public static void TimerStart() { try { timeBeginPeriod(1); } catch { } }
        public static void TimerStop() { try { timeEndPeriod(1); } catch { } }

        // Гамма-таблица дисплея: безопасное изменение цвета драйвером,
        // без оверлеев и без вмешательства в процесс игры.
        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool GetDeviceGammaRamp(IntPtr hdc, [Out] ushort[] lpRamp);
        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool SetDeviceGammaRamp(IntPtr hdc, [In] ushort[] lpRamp);

        public static ushort[] GammaGet()
        {
            IntPtr dc = IntPtr.Zero;
            try
            {
                dc = GetDC(IntPtr.Zero);
                if (dc == IntPtr.Zero) return null;
                ushort[] ramp = new ushort[768];
                if (!GetDeviceGammaRamp(dc, ramp)) return null;
                return ramp;
            }
            catch { return null; }
            finally { if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc); }
        }

        public static bool GammaSet(ushort[] ramp)
        {
            if (ramp == null || ramp.Length != 768) return false;
            IntPtr dc = IntPtr.Zero;
            try
            {
                dc = GetDC(IntPtr.Zero);
                if (dc == IntPtr.Zero) return false;
                return SetDeviceGammaRamp(dc, ramp);
            }
            catch { return false; }
            finally { if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc); }
        }
    }
}
'@

try { $null = [RustSuite.Theme] } catch {
    Add-Type -TypeDefinition $script:CsCode -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing', 'System' -ErrorAction Stop
}
