import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function ComingSoon({ title, description, plan }: { title: string; description: string; plan: string }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="text-muted-foreground text-sm">Built in {plan} — not implemented yet.</CardContent>
    </Card>
  );
}
