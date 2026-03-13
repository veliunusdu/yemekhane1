import { NextRequest, NextResponse } from 'next/server';

// Auth is handled client-side via Supabase (localStorage-based session).
// This proxy exists only to allow future server-side rules to be added here.
export default function proxy(_request: NextRequest) {
  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icons).*)'],
};
