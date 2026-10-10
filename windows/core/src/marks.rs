use crate::geometry::{Point, Rect};
use crate::tool::Tool;

#[derive(Clone, Debug, PartialEq)]
pub enum MarkKind {
    Stroke(Vec<Point>),
    Highlight(Vec<Point>),
    Arrow { from: Point, to: Point },
    Box(Rect),
}

/// One stroke or shape on a monitor.
#[derive(Clone, Debug, PartialEq)]
pub struct Mark {
    pub kind: MarkKind,
    pub color: String,
    pub width: f32,
}

/// Every mark on one monitor, newest last, with undo. Clearing is undoable too, so a slip of the
/// Delete key mid talk is one undo away.
#[derive(Default)]
pub struct Marks {
    all: Vec<Mark>,
    cleared: Option<Vec<Mark>>,
}

impl Marks {
    pub fn all(&self) -> &[Mark] {
        &self.all
    }

    pub fn is_empty(&self) -> bool {
        self.all.is_empty()
    }

    pub fn add(&mut self, mark: Mark) {
        self.all.push(mark);
        self.cleared = None;
    }

    pub fn undo(&mut self) {
        if self.all.is_empty() {
            if let Some(cleared) = self.cleared.take() {
                self.all = cleared;
            }
            return;
        }
        self.all.pop();
    }

    /// What the last clear took stays gone: undo no longer brings it back.
    pub fn keep_cleared(&mut self) {
        self.cleared = None;
    }

    pub fn clear(&mut self) {
        if self.all.is_empty() {
            return;
        }
        self.cleared = Some(std::mem::take(&mut self.all));
    }
}

/// Turning a press and a release into a shape.
pub struct Drag;

impl Drag {
    /// The box, a square in the direction dragged with Shift.
    pub fn rect(origin: Point, point: Point, shift: bool) -> Rect {
        let (mut dx, mut dy) = (point.x - origin.x, point.y - origin.y);
        if shift {
            let side = dx.abs().max(dy.abs());
            dx = side.copysign(dx);
            dy = side.copysign(dy);
        }
        Rect { x: origin.x.min(origin.x + dx), y: origin.y.min(origin.y + dy), width: dx.abs(), height: dy.abs() }
    }

    /// The arrow or box a drag makes; None for a click, which would only leave a speck.
    pub fn mark(tool: Tool, origin: Point, point: Point, shift: bool, color: &str, width: f32) -> Option<Mark> {
        let kind = match tool {
            Tool::Arrow => {
                let end = if shift { point.snapped45(origin) } else { point };
                (origin.distance(end) >= 4.0).then_some(MarkKind::Arrow { from: origin, to: end })?
            }
            Tool::Box => {
                let rect = Self::rect(origin, point, shift);
                (rect.width >= 3.0 || rect.height >= 3.0).then_some(MarkKind::Box(rect))?
            }
            _ => return None,
        };
        Some(Mark { kind, color: color.to_string(), width })
    }
}

/// A freehand stroke's points as the pointer gives them, leaving out ones too close to the last
/// to change the line.
#[derive(Default)]
pub struct StrokeBuilder {
    pub points: Vec<Point>,
}

impl StrokeBuilder {
    pub fn add(&mut self, point: Point) {
        if self.points.last().is_some_and(|last| last.distance(point) < 0.5) {
            return;
        }
        self.points.push(point);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dot(x: f32) -> Mark {
        Mark { kind: MarkKind::Stroke(vec![Point::new(x, 0.0)]), color: "#FF3B30".into(), width: 4.0 }
    }

    #[test]
    fn undo_takes_the_last_mark_off() {
        let mut marks = Marks::default();
        marks.add(dot(1.0));
        marks.add(dot(2.0));
        marks.undo();
        assert_eq!(marks.all(), &[dot(1.0)]);
    }

    #[test]
    fn undo_after_clear_brings_every_mark_back() {
        let mut marks = Marks::default();
        marks.add(dot(1.0));
        marks.add(dot(2.0));
        marks.clear();
        assert!(marks.is_empty());
        marks.undo();
        assert_eq!(marks.all(), &[dot(1.0), dot(2.0)]);
    }

    #[test]
    fn a_new_mark_after_clear_means_undo_takes_that_one_only() {
        let mut marks = Marks::default();
        marks.add(dot(1.0));
        marks.clear();
        marks.add(dot(2.0));
        marks.undo();
        assert!(marks.is_empty());
    }

    #[test]
    fn shift_makes_a_box_square_in_the_direction_dragged() {
        let origin = Point::new(100.0, 100.0);
        assert_eq!(Drag::rect(origin, Point::new(160.0, 120.0), true), Rect { x: 100.0, y: 100.0, width: 60.0, height: 60.0 });
        assert_eq!(Drag::rect(origin, Point::new(40.0, 80.0), true), Rect { x: 40.0, y: 40.0, width: 60.0, height: 60.0 });
    }

    #[test]
    fn a_click_is_no_shape() {
        let origin = Point::new(100.0, 100.0);
        assert!(Drag::mark(Tool::Arrow, origin, Point::new(102.0, 101.0), false, "#FF3B30", 4.0).is_none());
        assert!(Drag::mark(Tool::Box, origin, Point::new(101.0, 102.0), false, "#FF3B30", 4.0).is_none());
        assert!(Drag::mark(Tool::Box, origin, Point::new(150.0, 150.0), false, "#FF3B30", 4.0).is_some());
    }

    #[test]
    fn points_too_close_together_are_dropped() {
        let mut stroke = StrokeBuilder::default();
        stroke.add(Point::new(0.0, 0.0));
        stroke.add(Point::new(0.2, 0.1));
        stroke.add(Point::new(3.0, 0.0));
        assert_eq!(stroke.points, vec![Point::new(0.0, 0.0), Point::new(3.0, 0.0)]);
    }
}
