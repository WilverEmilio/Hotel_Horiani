export interface Reservation {
  id: number;
  guest_name: string;
  check_in: string;
  check_out: string;
  status: "pending" | "confirmed" | "cancelled" | "checked_in" | "checked_out";
}
