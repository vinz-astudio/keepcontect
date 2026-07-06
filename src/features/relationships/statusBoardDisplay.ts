export interface StatusBoardActivityLike {
  members: Array<{ alerted?: boolean }>
}

export interface StatusBoardGroupLike {
  id: string
  communityId: string | null
  act: StatusBoardActivityLike | null
}

export interface StatusBoardCommunityLike {
  id: string
}

export function statusGroupHasAlert(group: StatusBoardGroupLike): boolean {
  return group.act?.members.some((member) => member.alerted) ?? false
}

export function getDefaultOpenStatusKeys(
  groups: StatusBoardGroupLike[],
  communities: StatusBoardCommunityLike[],
): Set<string> {
  const knownCommunityIds = new Set(communities.map((community) => community.id))
  const keys = new Set<string>()

  for (const group of groups) {
    if (!statusGroupHasAlert(group)) continue

    keys.add('g:' + group.id)
    if (group.communityId && knownCommunityIds.has(group.communityId)) {
      keys.add('c:' + group.communityId)
    }
  }

  return keys
}
