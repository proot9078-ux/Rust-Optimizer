# ============================================================
#  ТЕМА И АНИМИРОВАННЫЕ КОНТРОЛЫ (C#)
# ============================================================
$script:CsCode = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
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
            for (Control x = c; x != null; x = x.Parent)
            {
                if (x is SmoothScrollPanel) return false;
                if (x is TextBoxBase || x is ListBox || x is ComboBox) return false;
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

    public class HeaderPanel : Panel, IAnim
    {
        private float _phase = 0.15f;
        public HeaderPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.PanelBg;
            Anim.Add(this);
        }
        public bool Tick()
        {
            _phase += 0.0038f;
            if (_phase > 1.35f) _phase = -0.25f;
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
                cb.Colors = new Color[] { Color.FromArgb(55, Theme.Accent), Color.FromArgb(150, Theme.AccentLt), Color.FromArgb(55, Theme.Accent) };
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
                cb.Colors = new Color[] { Color.FromArgb(0, Theme.Accent), Color.FromArgb(160, Theme.AccentLt), Color.FromArgb(0, Theme.Accent) };
                cb.Positions = new float[] { 0f, 0.5f, 1f };
                b.InterpolationColors = cb;
                g.FillRectangle(b, glow);
            }
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
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p);
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

    public class ProgressStrip : Control, IAnim
    {
        private double _v, _shown;
        private float _phase;
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
            if (shim) { _phase += 0.025f; if (_phase > 1f) _phase -= 1f; }
            Invalidate();
            return moving || shim;
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
            try { int v = 1; DwmSetWindowAttribute(f.Handle, 20, ref v, 4); DwmSetWindowAttribute(f.Handle, 19, ref v, 4); } catch { }
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
    }
}
'@

try { $null = [RustSuite.Theme] } catch {
    Add-Type -TypeDefinition $script:CsCode -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing', 'System' -ErrorAction Stop
}
