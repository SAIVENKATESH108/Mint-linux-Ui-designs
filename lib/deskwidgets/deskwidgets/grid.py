"""The grid every widget snaps to. A cell is a small card, medium is 2x1 cells, large is 2x2."""
from .catalog import SIZES

BASE_CELL = 170   # small card at 100 %
BASE_MARGIN = 4    # minimized transparent shadow margin around card (eliminates faint outline boxes)


class Grid:
    def __init__(self, screen_w, screen_h, settings):
        self.scale = float(settings.get('scale', 1.0))
        self.cell = round(BASE_CELL * self.scale)
        self.gap = int(settings.get('gap', 16))
        self.margin = round(BASE_MARGIN * self.scale)
        self.pitch = self.cell + self.gap
        side = int(settings.get('margin_side', 16))
        top = int(settings.get('margin_top', 44))       # 28px bar + 16px outer margin
        bottom = int(settings.get('margin_bottom', 72))  # Dock reservation
        self.cols = max(2, (screen_w - 2 * side + self.gap) // self.pitch)
        self.rows = max(2, (screen_h - top - bottom + self.gap) // self.pitch)
        # Anchor from the right edge with exactly 'side' outer margin
        self.x0 = screen_w - side - (self.cols * self.pitch - self.gap)
        self.y0 = top

    def card_px(self, size):
        cw, ch = SIZES[size]
        return cw * self.cell + (cw - 1) * self.gap, ch * self.cell + (ch - 1) * self.gap

    def window_px(self, size):
        w, h = self.card_px(size)
        return w + 2 * self.margin, h + 2 * self.margin

    def window_xy(self, col, row):
        return self.x0 + col * self.pitch - self.margin, self.y0 + row * self.pitch - self.margin

    def card_xy(self, col, row):
        return self.x0 + col * self.pitch, self.y0 + row * self.pitch

    def window_rect(self, col, row, size):
        wx, wy = self.window_xy(col, row)
        ww, wh = self.window_px(size)
        return wx, wy, ww, wh

    def card_rect(self, col, row, size):
        cx, cy = self.card_xy(col, row)
        cw, ch = self.card_px(size)
        return cx, cy, cw, ch

    def fits(self, col, row, size):
        cw, ch = SIZES[size]
        return 0 <= col <= self.cols - cw and 0 <= row <= self.rows - ch

    @staticmethod
    def cells(col, row, size):
        cw, ch = SIZES[size]
        return {(c, r) for c in range(col, col + cw) for r in range(row, row + ch)}

    def nearest_cell(self, win_x, win_y, size):
        cw, ch = SIZES[size]
        col = round((win_x + self.margin - self.x0) / self.pitch)
        row = round((win_y + self.margin - self.y0) / self.pitch)
        return min(max(col, 0), self.cols - cw), min(max(row, 0), self.rows - ch)

    def free_near(self, col, row, size, taken):
        """Free spot for `size` closest to (col, row), or None when the grid is full."""
        spots = [(c, r) for c in range(self.cols) for r in range(self.rows) if self.fits(c, r, size)]
        spots.sort(key=lambda p: ((p[0] - col) ** 2 + (p[1] - row) ** 2, p[1], p[0]))
        for c, r in spots:
            if not (self.cells(c, r, size) & taken):
                return c, r
        return None

    def first_free(self, size, taken):
        """New widgets fill the outer columns first, so the middle of the wallpaper stays clear."""
        cw, _ = SIZES[size]
        last = self.cols - cw
        order = []
        for i in range(last + 1):
            for c in (i, last - i):
                if c not in order and 0 <= c <= last:
                    order.append(c)
        for c in order:
            for r in range(self.rows):
                if self.fits(c, r, size) and not (self.cells(c, r, size) & taken):
                    return c, r
        return None

    def to_json(self, instances):
        """Description for the GNOME Shell helper that draws the grid while you drag."""
        return {
            'x0': self.x0, 'y0': self.y0, 'cols': self.cols, 'rows': self.rows, 'cell': self.cell,
            'gap': self.gap, 'pitch': self.pitch, 'margin': self.margin, 'radius': round(22 * self.scale),
            'widgets': {i['id']: {'col': i['col'], 'row': i['row'], 'w': SIZES[i['size']][0], 'h': SIZES[i['size']][1]}
                        for i in instances},
        }
