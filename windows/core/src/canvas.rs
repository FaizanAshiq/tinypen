//! What one monitor shows: its marks, and a white or black board over them with marks of its own,
//! the same as the Mac app.

use crate::marks::{Mark, Marks};

/// White or black, over the whole monitor, to sketch on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Board {
    White,
    Black,
}

/// What Esc erased, so undo brings all of it back, the board open as it was.
#[derive(Clone, Copy)]
struct Erased {
    screen: bool,
    sheet: bool,
    board: Option<Board>,
}

#[derive(Default)]
pub struct Canvas {
    board: Option<Board>,
    screen: Marks,
    sheet: Marks,
    erased: Option<Erased>,
}

impl Canvas {
    pub fn board(&self) -> Option<Board> {
        self.board
    }

    pub fn shows_board(&self) -> bool {
        self.board.is_some()
    }

    /// The marks showing: the board's while it is open, the screen's otherwise.
    pub fn marks(&self) -> &[Mark] {
        if self.board.is_none() { self.screen.all() } else { self.sheet.all() }
    }

    /// Nothing showing: no board, and no marks on the screen. Marks on a closed board wait for it.
    pub fn is_empty(&self) -> bool {
        self.board.is_none() && self.screen.is_empty()
    }

    pub fn add(&mut self, mark: Mark) {
        self.change(|marks| marks.add(mark));
    }

    /// Delete: what shows is cleared, and undo brings it back.
    pub fn clear(&mut self) {
        self.change(Marks::clear);
    }

    pub fn undo(&mut self) {
        let Some(erased) = self.erased.take() else { return self.change(Marks::undo) };
        if erased.screen {
            self.screen.undo();
        }
        if erased.sheet {
            self.sheet.undo();
        }
        self.board = erased.board;
    }

    /// Esc: everything drawn gone, on the screen and on the board, and the board closed. Undo brings
    /// it all back. Reported on the Mac: undo brought back only the screen's marks, and the board's
    /// were lost.
    pub fn erase(&mut self) {
        self.erased = Some(Erased { screen: !self.screen.is_empty(), sheet: !self.sheet.is_empty(), board: self.board });
        self.screen.clear();
        self.sheet.clear();
        self.board = None;
    }

    /// Every mark gone, the board too: the screen as it was.
    pub fn reset(&mut self) {
        *self = Canvas::default();
    }

    /// White, then black, then off.
    pub fn cycle_board(&mut self) {
        self.board = match self.board {
            None => Some(Board::White),
            Some(Board::White) => Some(Board::Black),
            Some(Board::Black) => None,
        };
    }

    /// Drawing mode ended: the board closes and keeps its marks for next time. Reported on the Mac:
    /// left open, it hid every app while clicks went through to them.
    pub fn close_board(&mut self) {
        self.board = None;
    }

    fn change(&mut self, change: impl FnOnce(&mut Marks)) {
        self.erased = None;
        if self.board.is_none() { change(&mut self.screen) } else { change(&mut self.sheet) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::Point;
    use crate::marks::MarkKind;

    fn mark(x: f32) -> Mark {
        Mark { kind: MarkKind::Stroke(vec![Point::new(x, 0.0), Point::new(x + 10.0, 10.0)]), color: "#FF3B30".into(), width: 4.0 }
    }

    #[test]
    fn undo_after_esc_brings_back_the_board_as_it_was() {
        let mut canvas = Canvas::default();
        canvas.add(mark(1.0));
        canvas.cycle_board();
        canvas.add(mark(2.0));
        canvas.erase();
        assert!(canvas.board().is_none() && canvas.is_empty());
        canvas.undo();
        assert_eq!(canvas.board(), Some(Board::White));
        assert_eq!(canvas.marks(), [mark(2.0)]);
        canvas.cycle_board();
        canvas.cycle_board();
        assert_eq!(canvas.marks(), [mark(1.0)]);
    }

    #[test]
    fn a_mark_drawn_after_esc_is_what_undo_takes_back() {
        let mut canvas = Canvas::default();
        canvas.add(mark(1.0));
        canvas.erase();
        canvas.add(mark(2.0));
        canvas.undo();
        assert!(canvas.is_empty());
    }

    #[test]
    fn esc_leaves_an_older_delete_alone() {
        let mut canvas = Canvas::default();
        canvas.add(mark(1.0));
        canvas.clear();
        canvas.cycle_board();
        canvas.add(mark(2.0));
        canvas.erase();
        canvas.undo();
        assert_eq!(canvas.marks(), [mark(2.0)]);
        canvas.cycle_board();
        canvas.cycle_board();
        assert!(canvas.marks().is_empty());
    }

    #[test]
    fn closing_the_board_keeps_its_marks_for_next_time() {
        let mut canvas = Canvas::default();
        canvas.cycle_board();
        canvas.add(mark(1.0));
        canvas.close_board();
        assert!(canvas.board().is_none() && canvas.is_empty());
        canvas.cycle_board();
        assert_eq!(canvas.marks(), [mark(1.0)]);
    }

    #[test]
    fn only_what_shows_counts() {
        let mut canvas = Canvas::default();
        assert!(canvas.is_empty());
        canvas.cycle_board();
        assert!(!canvas.is_empty());
        assert!(canvas.shows_board());
    }
}
