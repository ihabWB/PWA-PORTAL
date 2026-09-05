import { Alert, Card, Chip } from "@heroui/react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";

import type { Locale } from "@/i18n/config";
import type { EntryTaskList } from "@/lib/data/entry-tasks";
import { formatVolume } from "@/lib/format";

type TaskListProps = {
  list: EntryTaskList;
  locale: Locale;
};

/** One row per measurement point; entered points are ticked off with their value. */
export async function TaskList({ list, locale }: TaskListProps) {
  const t = await getTranslations("entry");
  const tc = await getTranslations("common");
  const ta = await getTranslations("assetType");
  const tv = await getTranslations("validation");

  if (list.tasks.length === 0) {
    return (
      <Alert status="accent">
        <Alert.Indicator />
        <Alert.Content>
          <Alert.Description>{t("noTasks")}</Alert.Description>
        </Alert.Content>
      </Alert>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <span className="text-muted text-sm">
          {t("progress", { done: list.done, total: list.tasks.length })}
        </span>
        {list.pending === 0 && (
          <Chip size="sm" variant="soft" color="success">
            {t("allDone")}
          </Chip>
        )}
      </div>

      <ul className="flex flex-col gap-2">
        {list.tasks.map((task) => {
          const entered = task.readingId !== null;
          return (
            <li key={task.pointId}>
              <Card>
                <Card.Content className="py-3">
                  <Link
                    href={`/field-entry/${task.pointId}?date=${list.date}`}
                    className="flex items-center justify-between gap-3"
                  >
                    <span className="flex min-w-0 flex-col gap-1">
                      <span className="truncate font-medium">
                        {locale === "ar" ? task.nameAr : (task.nameEn ?? task.nameAr)}
                      </span>
                      <span className="text-muted flex flex-wrap items-center gap-2 text-xs">
                        <span className="font-mono">{task.code}</span>
                        {task.assetType && <span>{ta(task.assetType)}</span>}
                        {task.isAssigned && (
                          <Chip size="sm" variant="soft">
                            {t("assigned")}
                          </Chip>
                        )}
                      </span>
                    </span>

                    <span className="flex shrink-0 items-center gap-2">
                      {entered ? (
                        <>
                          {task.validationStatus === "FLAGGED" && (
                            <Chip size="sm" variant="soft" color="warning">
                              {tv("FLAGGED")}
                            </Chip>
                          )}
                          <span className="font-mono text-sm whitespace-nowrap">
                            {formatVolume(task.volumeM3 ?? 0, locale)}
                            <span className="text-muted ms-1 text-xs">{tc("unitM3")}</span>
                          </span>
                          <Chip size="sm" variant="soft" color="success">
                            {t("done")}
                          </Chip>
                        </>
                      ) : (
                        <Chip size="sm" variant="soft" color="warning">
                          {t("pending")}
                        </Chip>
                      )}
                    </span>
                  </Link>
                </Card.Content>
              </Card>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
